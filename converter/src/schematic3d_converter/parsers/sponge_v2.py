"""Sponge v2 `.schem` reader (WorldEdit 7 style, big-endian gzip NBT).

Layout: root["Schematic"] with Version=2, Width/Height/Length ints,
Palette (blockstate-string → index dict) and BlockData (unsigned LEB128
varints). Iteration order: x fastest, then z, then y.
"""
from __future__ import annotations

from pathlib import Path

from ..mapping import map_java_entry
from ..models import BlockEntry, Design, Layer, PaletteEntry
from ..nbt import NbtError, read_nbt
from ..validate import ValidationReport


class Sponge2Error(Exception):
    pass


def split_blockstate(key: str) -> PaletteEntry:
    """`minecraft:x[a=1,b=true]` → PaletteEntry."""
    key = key.strip()
    if "[" in key:
        base, rest = key.split("[", 1)
        states_s = rest.rstrip("]")
        states: dict = {}
        for part in _split_states(states_s):
            if not part or "=" not in part:
                continue
            k, v = part.split("=", 1)
            k = k.strip()
            v = v.strip()
            if v.lower() in ("true", "false"):
                val = v.lower() == "true"
            else:
                try:
                    val = int(v)
                except ValueError:
                    val = v
            states[k] = val
    else:
        base, states = key, {}
    if ":" not in base:
        base = f"minecraft:{base}"
    if base.startswith("bedrock:"):
        base = "minecraft:" + base.split(":", 1)[1]
    return PaletteEntry.make(base, states)


def _split_states(s: str):
    out, buf, depth = [], "", 0
    for ch in s:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(buf)
            buf = ""
        else:
            buf += ch
    if buf:
        out.append(buf)
    return out


def _read_varints(data: list[int], count: int) -> list[int]:
    out: list[int] = []
    i = 0
    while len(out) < count and i < len(data):
        shift = 0
        val = 0
        while True:
            if i >= len(data):
                raise Sponge2Error("truncated varint stream")
            byte = data[i] & 0xFF
            i += 1
            val |= (byte & 0x7F) << shift
            if not byte & 0x80:
                break
            shift += 7
            if shift > 28:
                raise Sponge2Error("varint too large")
        out.append(val)
    if len(out) != count:
        raise Sponge2Error(f"BlockData shorter than volume ({len(out)} < {count})")
    return out


def parse_file(path: Path):
    design, rep, conv = parse_bytes(path.read_bytes(), source_name=path.stem)
    return design, rep, conv


def parse_bytes(data: bytes, *, source_name: str = "sponge2"):
    rep = ValidationReport()
    try:
        _, root = read_nbt(data, little_endian=False)
    except NbtError as exc:
        raise Sponge2Error(f"malformed NBT: {exc}") from exc
    body = root.get("Schematic")
    if not isinstance(body, dict) or body.get("Version") != 2:
        raise Sponge2Error("not a Sponge v2 schematic")

    def iv(k):
        v = body.get(k)
        if not isinstance(v, int):
            raise Sponge2Error(f"missing/invalid {k}")
        return v

    w, h, l = iv("Width"), iv("Height"), iv("Length")
    if not all(1 <= v <= 512 for v in (w, h, l)):
        raise Sponge2Error(f"dimensions {w}x{h}x{l} outside 1..512")
    pal = body.get("Palette")
    if not isinstance(pal, dict) or not pal:
        raise Sponge2Error("missing Palette map")
    block_data = body.get("BlockData")
    if not isinstance(block_data, list):
        raise Sponge2Error("missing BlockData")

    index_to_state: dict[int, str] = {}
    for state_str, idx in pal.items():
        if not isinstance(idx, int) or idx < 0:
            rep.warning("sponge2.palette", f"bad palette index for {state_str!r}")
            continue
        index_to_state[idx] = str(state_str)

    n = w * h * l
    order = _read_varints([int(x) for x in block_data], n)

    palette_out: list[PaletteEntry] = []
    conv_entries: list[dict] = []
    java_to_bedrock: dict[str, int | None] = {}
    for idx in sorted(index_to_state):
        state_key = index_to_state[idx]
        java_pe = split_blockstate(state_key)
        if java_pe.id.endswith(":air"):
            java_to_bedrock[state_key] = None
            conv_entries.append({"java": state_key, "action": "air", "bedrock": None,
                                 "note": ""})
            continue
        outcome = map_java_entry(java_pe)
        rec = {"java": state_key, "action": outcome.action, "note": outcome.note}
        if outcome.entry is None or outcome.action == "unsupported":
            java_to_bedrock[state_key] = None
            rec["bedrock"] = None
        else:
            pe = outcome.entry
            rec["bedrock"] = pe.id + (
                "[" + ",".join(f"{k}={v}" for k, v in pe.states) + "]"
                if pe.states else "")
            if pe not in palette_out:
                palette_out.append(pe)
            java_to_bedrock[state_key] = palette_out.index(pe)
        conv_entries.append(rec)

    blocks: list[BlockEntry] = []
    dropped = 0
    for i, idx in enumerate(order):
        state_key = index_to_state.get(idx)
        if state_key is None:
            dropped += 1
            continue
        mapped = java_to_bedrock.get(state_key)
        if mapped is None:
            if not state_key.endswith(":air") and "[minecraft:air" not in state_key:
                dropped += 1
            continue
        # order: x fastest, then z, then y
        x = i % w
        z = (i // w) % l
        y = i // (w * l)
        blocks.append(BlockEntry(x, y, z, mapped))

    conv = {"entries": conv_entries, "droppedBlocks": dropped}
    if not blocks:
        raise Sponge2Error("no blocks left after mapping")
    meta = {}
    md = body.get("Metadata")
    if isinstance(md, dict):
        if isinstance(md.get("Name"), str):
            meta["originalName"] = md["Name"]
        if isinstance(md.get("Author"), str):
            meta["originalAuthor"] = md["Author"]
    meta.update({"source": "schematic3d sponge-v2", "generator": "schematic3d_converter"})
    name = meta.get("originalName") or source_name

    design = Design(
        name=str(name)[:200], description="Imported from Sponge v2 .schem",
        dimensions=(w, h, l), palette=palette_out, blocks=blocks,
        layers=[Layer("all", "All layers", 0, h - 1)],
        metadata=meta,
    )
    if dropped:
        rep.warning("sponge2.dropped",
                    f"{dropped} block(s) had no Bedrock mapping and were dropped")
    return design, rep, conv
