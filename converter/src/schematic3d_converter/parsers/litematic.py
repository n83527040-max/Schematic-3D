"""Litematica `.schem` reader (big-endian, gzip NBT, sponge v2 style).

Reference layout (Litematica writer, stable across versions):
- root: {"Litematic": {...}} — older writers put fields at root; both handled.
- Regions.<name>: {Size:[3 int], Position:[3 int], BlockStates: LongArray,
  Palette: [{Name, Properties}], BlockCount:int, TileEntities, Entities}
- Bit packing: bitsPerBlock = max(2, ceil(log2(len(Palette)))); entries are
  packed LSB-first across consecutive 64-bit big-endian longs.

Data lives in Java coordinates; palette entries are converted to Bedrock ids
via the mapping module; unmapped entries are dropped with report entries.
"""
from __future__ import annotations

import math
from pathlib import Path

from ..mapping import map_java_entry
from ..models import BlockEntry, Design, Layer, PaletteEntry
from ..nbt import NbtError, ListTag, read_nbt
from ..validate import ValidationReport


class LitematicError(Exception):
    pass


def parse_file(path: Path, *, prefer_region: str | None = None):
    design, rep, conv = parse_bytes(path.read_bytes(), source_name=path.stem,
                                    prefer_region=prefer_region)
    return design, rep, conv


def parse_bytes(data: bytes, *, source_name: str = "litematic",
                prefer_region: str | None = None):
    """Returns (design, validation_report, conversion_report).

    conversion_report is a dict: {"entries":[...], "droppedBlocks":N}
    """
    rep = ValidationReport()
    try:
        _, root = read_nbt(data, little_endian=False)
    except NbtError as exc:
        raise LitematicError(f"malformed litematic NBT: {exc}") from exc

    body = root.get("Litematic") if isinstance(root.get("Litematic"), dict) else root
    regions = body.get("Regions")
    if not isinstance(regions, dict) or not regions:
        raise LitematicError("no Regions compound found — not a litematic file?")
    name = prefer_region if prefer_region in regions else next(iter(regions))
    if prefer_region and prefer_region not in regions:
        rep.warning("litematic.region",
                    f"requested region {prefer_region!r} missing; using {name!r}")
    region = regions[name]
    if not isinstance(region, dict):
        raise LitematicError("region compound malformed")

    size = region.get("Size")
    if isinstance(size, ListTag):
        size = size.items
    if not isinstance(size, (list, tuple)) or len(size) != 3:
        raise LitematicError("region missing Size[x,y,z]")
    sx, sy, sz = (abs(int(v)) for v in size)
    if not all(1 <= v <= 512 for v in (sx, sy, sz)):
        raise LitematicError(f"region size {sx}x{sy}x{sz} outside supported 1..512")

    palette_raw = region.get("Palette")
    if isinstance(palette_raw, ListTag):
        palette_raw = palette_raw.items
    if not isinstance(palette_raw, list) or not palette_raw:
        raise LitematicError("region missing Palette")

    mapping_entries = []
    bedrock_palette: list[PaletteEntry] = []
    palette_map: dict[int, int | None] = {}
    for i, entry in enumerate(palette_raw):
        if not isinstance(entry, dict) or "Name" not in entry:
            mapping_entries.append({"java": str(entry), "action": "unsupported",
                                    "note": "malformed palette entry"})
            palette_map[i] = None
            continue
        jname = str(entry["Name"])
        props = entry.get("Properties") or {}
        if isinstance(props, dict):
            states = {str(k): _prop_val(v) for k, v in props.items()}
        else:
            states = {}
        java_pe = PaletteEntry.make(_namespace(jname), states)
        outcome = map_java_entry(java_pe)
        rec = {"java": java_pe.id + (
            "[" + ",".join(f"{k}={v}" for k, v in java_pe.states) + "]"
            if java_pe.states else ""),
            "action": outcome.action, "note": outcome.note}
        if outcome.entry is not None and outcome.action != "unsupported":
            rec["bedrock"] = outcome.entry.id + (
                "[" + ",".join(f"{k}={v}" for k, v in outcome.entry.states) + "]"
                if outcome.entry.states else "")
            if outcome.entry not in bedrock_palette:
                bedrock_palette.append(outcome.entry)
            palette_map[i] = bedrock_palette.index(outcome.entry)
        else:
            rec["bedrock"] = None
            palette_map[i] = None
        mapping_entries.append(rec)
    rep.warning("litematic.mapping",
                "Java→Bedrock mapping applied; see conversionReport for the "
                f"{sum(1 for m in mapping_entries if m['action'] in ('unsupported', 'family-unresolved'))}"
                " affected entries")

    block_states = region.get("BlockStates")
    if block_states is None:
        raise LitematicError("region missing BlockStates")
    n = sx * sy * sz
    bits = max(2, int(math.ceil(math.log2(max(2, len(palette_raw))))))
    per_long = 64 // bits
    cap = per_long * ((n + per_long - 1) // per_long)  # padded total entries

    if isinstance(block_states, ListTag):
        longs = block_states.items
    else:
        longs = block_states

    blocks: list[BlockEntry] = []
    dropped = 0
    idx = 0

    def _is_air(entry) -> bool:
        return isinstance(entry, dict) and str(entry.get("Name", "")).lower().endswith(":air")

    air_indices = {i for i, e in enumerate(palette_raw) if _is_air(e)}
    mask = (1 << bits) - 1
    longs = [int(w) & 0xFFFFFFFFFFFFFFFF for w in longs]
    for l_i, word in enumerate(longs):
        entries_this = min(cap - l_i * per_long, per_long)
        for e_i in range(entries_this):
            if idx >= n:
                break
            shift = e_i * bits
            val = (word >> shift) & mask
            x = idx // (sy * sz)
            rem = idx % (sy * sz)
            y = rem // sz
            z = rem % sz
            idx += 1
            if val in air_indices:
                continue
            mapped = palette_map.get(val)
            if mapped is None:
                dropped += 1
                continue
            blocks.append(BlockEntry(x, y, z, mapped))

    conv = {"entries": mapping_entries, "droppedBlocks": dropped}
    if not blocks:
        raise LitematicError("no blocks left after mapping (all palette entries unsupported?)")

    design = Design(
        name=source_name,
        description=f"Imported from litematic region {name!r}",
        dimensions=(sx, sy, sz),
        palette=bedrock_palette,
        blocks=blocks,
        layers=[Layer("all", "All layers", 0, sy - 1)],
        metadata={"source": "litematic", "generator": "schematic3d_converter",
                  "region": name,
                  "unsupportedFeatures": [m["java"] for m in mapping_entries
                                          if m["action"] == "unsupported"][:64]},
    )
    if dropped:
        rep.warning("litematic.dropped",
                    f"{dropped} block(s) use palette entries with no Bedrock "
                    f"equivalent and were removed from the converted design",
                    "$.blocks")
    return design, rep, conv


def _namespace(name: str) -> str:
    if ":" in name:
        ns, rest = name.split(":", 1)
        if ns == "bedrock":
            ns = "minecraft"
        return f"{ns}:{rest}"
    return f"minecraft:{name}"


def _prop_val(v):
    if isinstance(v, str):
        low = v.lower()
        if low in ("true", "false"):
            return low == "true"
        try:
            return int(v)
        except ValueError:
            return v
    return v


