"""Bedrock `.mcstructure` reader (little-endian NBT).

Reference: wiki.bedrock.dev/nbt/mcstructure (verified 2026-10-29).
Layout facts we rely on:
- size = [x, y, z] ints; indices proceed in ZYX order:
  index = (x * sizeY + y) * sizeZ + z
- structure.block_indices: two int lists (primary + secondary layer).
- -1 index = structure void (keep existing block on placement).
- structure.palette.default.block_palette: list of {name, states, version}.
"""
from __future__ import annotations

from pathlib import Path

from ..models import BlockEntry, Design, Layer, PaletteEntry
from ..nbt import ListTag, NbtError, read_nbt
from ..validate import ValidationReport


class McstructureError(Exception):
    pass


def _unwrap(v):
    """ListTag → python list, recursively for dict values inside compounds."""
    if isinstance(v, ListTag):
        return [_unwrap(x) for x in v.items]
    if isinstance(v, dict):
        return {k: _unwrap(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_unwrap(x) for x in v]
    return v


def parse_file(path: Path) -> tuple[Design, ValidationReport]:
    return parse_bytes(path.read_bytes(), source_name=path.stem)


def parse_bytes(data: bytes, *, source_name: str = "structure") -> tuple[Design, ValidationReport]:
    rep = ValidationReport()
    try:
        _, raw = read_nbt(data, little_endian=True)
    except NbtError as exc:
        raise McstructureError(f"malformed mcstructure NBT: {exc}") from exc
    root = _unwrap(raw)

    fv = root.get("format_version")
    if fv != 1:
        rep.warning("mcstructure.format_version",
                    f"format_version={fv!r} (expected 1); attempting to continue")
    size = root.get("size")
    if not isinstance(size, list) or len(size) != 3 or not all(isinstance(v, int) for v in size):
        raise McstructureError("missing or malformed 'size' list")
    sx, sy, sz = (int(v) for v in size)
    if not all(1 <= v <= 1024 for v in (sx, sy, sz)):
        raise McstructureError(f"structure size {sx}x{sy}x{sz} out of sane range 1..1024")

    structure = root.get("structure")
    if not isinstance(structure, dict):
        raise McstructureError("missing 'structure' compound")
    bi = structure.get("block_indices")
    if not isinstance(bi, list) or len(bi) != 2:
        raise McstructureError("'block_indices' must contain exactly two lists")
    primary, secondary = bi[0], bi[1]
    n = sx * sy * sz
    if len(primary) != n or len(secondary) != n:
        raise McstructureError(
            f"block_indices length mismatch: {len(primary)}/{len(secondary)} vs {n}")

    palette = structure.get("palette", {})
    default = palette.get("default", {}) if isinstance(palette, dict) else {}
    raw_palette = default.get("block_palette", [])
    if not isinstance(raw_palette, list):
        raise McstructureError("block_palette must be a list")

    entries: list[PaletteEntry] = []
    for i, e in enumerate(raw_palette):
        if not isinstance(e, dict) or "name" not in e:
            rep.warning("mcstructure.palette", f"palette entry {i} malformed; treated as air")
            entries.append(PaletteEntry.make("minecraft:air", {}))
            continue
        name = str(e["name"])
        if ":" not in name:
            name = f"minecraft:{name}"
        states = {}
        st = e.get("states")
        if isinstance(st, dict):
            for k, v in st.items():
                states[str(k)] = _coerce_state(v)
        entries.append(PaletteEntry.make(name, states))

    blocks: list[BlockEntry] = []
    for idx in range(n):
        pi = primary[idx]
        if not isinstance(pi, int) or pi < 0 or pi >= len(entries):
            continue
        if entries[pi].id == "minecraft:air":
            continue
        z = idx % sz
        y = (idx // sz) % sy
        x = idx // (sz * sy)
        blocks.append(BlockEntry(x, y, z, pi))
        # secondary (co-located) layer, e.g. waterlogging: recorded as warning
        # counts only; we do not fabricate combined-state support here.
        si = secondary[idx]
        if isinstance(si, int) and si >= 0 and si < len(entries):
            rep.warning("mcstructure.colocated",
                        f"co-located block at ({x},{y},{z}) ignored "
                        f"({entries[si].id}); Bedrock colocation not representable "
                        f"in schematic3d-build v1")

    if not blocks:
        raise McstructureError("structure contains no non-air blocks")

    design = Design(
        name=source_name,
        description=None,
        dimensions=(sx, sy, sz),
        palette=entries,
        blocks=blocks,
        layers=[Layer("all", "كل الطبقات / All layers", 0, max(0, sy - 1))],
        metadata={"source": "mcstructure", "generator": "schematic3d_converter",
                  "note": "Parsed from .mcstructure; y range kept as in file."},
    )
    return design, rep


def _coerce_state(v):
    if isinstance(v, list):  # ByteArray payloads come back as list[int]
        if len(v) == 1:
            return bool(v[0])
        return v
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v
    return v
