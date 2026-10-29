"""Bedrock `.mcstructure` writer.

Produces a structure file loadable via `/structure load` / structure blocks.
Palette entries carry `version` = the documented current state-version value
(18168865 as of 1.26.30 per wiki.bedrock.dev) so vanilla skips its legacy
upgrade chain. We cannot execute the game in CI; loading in-game remains a
manual acceptance test (docs/05).
"""
from __future__ import annotations

from pathlib import Path

from ..models import Design
from ..nbt import ListTag, NbtInt, TAG_COMPOUND, TAG_INT, TAG_INT_ARRAY, write_nbt

BLOCK_VERSION = 18168865  # documented for 1.26.30 (0x01153C21)


def design_to_nbt(design: Design) -> dict:
    sx, sy, sz = design.dimensions
    n = sx * sy * sz
    palette_index: dict = {}
    palette_list: list[dict] = []
    for pe in design.palette:
        key = pe
        if key not in palette_index:
            palette_index[key] = len(palette_list)
            palette_list.append({
                "name": pe.id,
                "states": {k: _state_value(v) for k, v in pe.states},
                "version": NbtInt(BLOCK_VERSION),
            })

    primary = [-1] * n
    secondary = [-1] * n
    for b in design.blocks:
        if not (0 <= b.x < sx and 0 <= b.y < sy and 0 <= b.z < sz):
            continue
        pe = design.palette[b.palette_index]
        idx = palette_index.get(pe)
        if idx is None:
            continue
        flat = (b.x * sy + b.y) * sz + b.z
        primary[flat] = idx

    return {
        "format_version": NbtInt(1),
        "size": ListTag(TAG_INT, [NbtInt(sx), NbtInt(sy), NbtInt(sz)]),
        "structure": {
            "block_indices": ListTag(TAG_INT_ARRAY, [primary, secondary]),
            "entities": ListTag(10, []),
            "palette": {
                "default": {
                    "block_palette": ListTag(TAG_COMPOUND, palette_list),
                    "block_position_data": {},
                }
            },
        },
        "structure_world_origin": ListTag(
            TAG_INT, [NbtInt(0), NbtInt(0), NbtInt(0)]),
    }


def _state_value(v):
    if isinstance(v, bool):
        return v  # writer emits TAG_Byte for bools, which Bedrock expects
    if isinstance(v, int):
        return NbtInt(v)
    return v


def write_file(design: Design, path: Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    root = design_to_nbt(design)
    data = write_nbt(root, name="", little_endian=True)
    path.write_bytes(data)
    return path
