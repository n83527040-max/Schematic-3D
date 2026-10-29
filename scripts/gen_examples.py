#!/usr/bin/env python3
"""Generate the example designs shipped with the app and used by tests.

Outputs (default examples/):
  cottage-12x8x12.json      small house, layers+rooms, schematic3d-build v1
  tower-9x18x9.json         tower with battlements
  arch-bridge-21x9x7.json   bridge demo
  cottage-12x8x12.mcstructure   Bedrock structure twin of the cottage
  broken-*.json             intentionally invalid files for failure-path tests
The same generator is used by `converter/tests` via import, keeping fixtures
and tests in lockstep.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "converter" / "src"))

from schematic3d_converter.models import BlockEntry, Design, Layer, PaletteEntry, Room
from schematic3d_converter.exporters.mcstructure_out import write_file as write_mcstructure


def _pal(palette: list[PaletteEntry], cache: dict, bid: str, states: dict | None = None) -> int:
    pe = PaletteEntry.make(bid, states or {})
    if pe not in cache:
        cache[pe] = len(palette)
        palette.append(pe)
    return cache[pe]


def cottage() -> Design:
    """12x8x12 two-floor house with rooms: hall, kitchen, bedroom."""
    W, H, D = 12, 8, 12
    palette: list[PaletteEntry] = []
    cache: dict = {}
    p_stone = _pal(palette, cache, "minecraft:stone")
    p_cobble = _pal(palette, cache, "minecraft:cobblestone")
    p_planks = _pal(palette, cache, "minecraft:oak_planks")
    p_log = _pal(palette, cache, "minecraft:oak_log")
    p_glass = _pal(palette, cache, "minecraft:glass")
    p_roof = _pal(palette, cache, "minecraft:red_nether_brick")
    p_door_l = _pal(palette, cache, "minecraft:iron_door", {"upper_block_bit": False, "open_bit": False})
    p_torch = _pal(palette, cache, "minecraft:torch")

    cells: dict[tuple[int, int, int], int] = {}

    def put(x, y, z, p):
        if 0 <= x < W and 0 <= y < H and 0 <= z < D:
            cells[(x, y, z)] = p  # later writes overwrite (roof replaces wall tops)

    # floor
    for x in range(W):
        for z in range(D):
            put(x, 0, z, p_planks)
    # walls + corner logs
    for y in range(1, 6):
        for x in range(W):
            for z in range(D):
                on_wall = x in (0, W - 1) or z in (0, D - 1)
                if not on_wall:
                    continue
                p = p_log if (x in (0, W - 1) and z in (0, D - 1)) else p_planks
                # windows mid-wall floor1
                if y in (2, 3) and (x in (3, 4, 7, 8) and z in (0, D - 1) or
                                    z in (3, 4, 7, 8) and x in (0, W - 1)) and p == p_planks:
                    p = p_glass
                put(x, y, z, p)
    # front door opening (overwrite: door leaf at y=1, glass transom at y=2)
    for y in (1, 2):
        for x in (5, 6):
            put(x, y, 0, p_door_l if y == 1 else p_glass)
    # interior partition floor1: two rooms
    for x in range(1, W - 1):
        put(x, 1, 7, p_planks)
        put(x, 2, 7, p_planks)
        if not (5 <= x <= 6):
            put(x, 3, 7, p_planks)
    # floor2 + ceiling
    for x in range(W):
        for z in range(D):
            put(x, 5, z, p_planks)
    # upper room walls
    for y in range(6, 8):
        for x in range(W):
            for z in range(D):
                if x in (0, W - 1) or z in (0, D - 1):
                    put(x, y, z, p_planks if y == 6 else p_log)
    # roof: pyramidal overhang at y=8? H=8 so top walls 6,7 then roof slab at 7 edges
    for x in range(-1, W + 1):
        for z in range(-1, D + 1):
            if x in (-1, W) or z in (-1, D):
                continue
            edge = x in (0, W - 1) or z in (0, D - 1)
            if edge:
                put(x, 7, z, p_roof)
    # torches inside
    put(2, 2, 6, p_torch)
    put(9, 2, 6, p_torch)
    put(2, 6, 6, p_torch)
    put(6, 2, 0, p_torch)

    layers = [Layer("floor_1", "الطابق الأرضي / Ground floor", 0, 4),
              Layer("floor_2", "الطابق العلوي / Upper floor", 5, 7)]
    rooms = [Room("hall", "البهو / Hall", "floor_1", (1, 1, W - 2, 6)),
             Room("kitchen", "المطبخ / Kitchen", "floor_1", (1, 8, W - 2, D - 2)),
             Room("bedroom", "غرفة النوم / Bedroom", "floor_2", (1, 1, W - 2, D - 2))]
    return Design(
        name="Cottage 12×8×12",
        description="منزل صغير بطابقين: بهو، مطبخ وغرفة نوم علوية. مثال مُولّد لاختبار التطبيق والمود.",
        dimensions=(W, H, D),
        palette=palette,
        blocks=[BlockEntry(x, y, z, p) for (x, y, z), p in cells.items()],
        layers=layers, rooms=rooms,
        metadata={"generator": "scripts/gen_examples.py", "source": "schematic3d",
                  "notes": ["مثال كامل البنية: كل إحداثية فريدة وكل paletteIndex صالح."],
                  "unsupportedFeatures": []},
    )


def tower() -> Design:
    S, H = 9, 18
    palette: list[PaletteEntry] = []
    cache: dict = {}
    p_cobble = _pal(palette, cache, "minecraft:cobblestone")
    p_mossy = _pal(palette, cache, "minecraft:mossy_cobblestone")
    p_log = _pal(palette, cache, "minecraft:spruce_log")
    p_planks = _pal(palette, cache, "minecraft:spruce_planks")
    p_glass = _pal(palette, cache, "minecraft:glass")
    p_torch = _pal(palette, cache, "minecraft:torch")
    blocks: list[BlockEntry] = []

    def put(x, y, z, p):
        blocks.append(BlockEntry(x, y, z, p))

    seen = set()
    def putu(x, y, z, p):
        if (x, y, z) in seen:
            return
        seen.add((x, y, z))
        put(x, y, z, p)

    half = S // 2
    for y in range(H):
        for x in range(S):
            for z in range(S):
                border = x in (0, S - 1) or z in (0, S - 1)
                if border:
                    p = p_mossy if (x + z + y * 3) % 7 == 0 else p_cobble
                    putu(x, y, z, p)
        # corner towers in logs
        for cx, cz in ((0, 0), (0, S - 1), (S - 1, 0), (S - 1, S - 1)):
            putu(cx, y, cz, p_log)
    # floors every 4 levels
    for fy in (3, 7, 11):
        for x in range(1, S - 1):
            for z in range(1, S - 1):
                if (x == half or z == half) and not (x in (0, S-1) or z in (0, S-1)):
                    continue
                if x in (half,) or z in (half,):
                    putu(x, fy, z, p_planks)
                elif x % 2 == 0 and z % 2 == 0:
                    putu(x, fy, z, p_planks)
    # windows
    for fy in (2, 6, 10):
        putu(half, fy, 0, p_glass)
        putu(half, fy, S - 1, p_glass)
        putu(0, fy, half, p_glass)
        putu(S - 1, fy, half, p_glass)
    # top platform + battlements
    top = H - 1
    for x in range(S):
        for z in range(S):
            putu(x, top - 1, z, p_planks if (x == 0 or z == 0 or x == S-1 or z == S-1) else p_cobble)
    for x in range(S):
        for z in range(S):
            if (x in (0, S - 1) or z in (0, S - 1)) and (x + z) % 2 == 0:
                putu(x, top, z, p_cobble)
    putu(half, 4, half, p_torch)
    layers = [Layer("level_1", "الطابق 1", 0, 3), Layer("level_2", "الطابق 2", 4, 7),
              Layer("level_3", "الطابق 3", 8, 11), Layer("crown", "التاج / Crown", 12, H - 1)]
    return Design(
        name="Watch Tower 9×18×9",
        description="برج مراقبة حجري بأربعة طوابق وشرفات علوية. مثال مُولّد لاختبار الطبقات.",
        dimensions=(S, H, S), palette=palette, blocks=dedupe(blocks),
        layers=layers,
        metadata={"generator": "scripts/gen_examples.py", "source": "schematic3d"},
    )


def dedupe(blocks: list[BlockEntry]) -> list[BlockEntry]:
    seen = set()
    out = []
    for b in blocks:
        k = b.key()
        if k in seen:
            continue
        seen.add(k)
        out.append(b)
    return out


def bridge() -> Design:
    W, H, D = 21, 9, 7
    palette: list[PaletteEntry] = []
    cache: dict = {}
    p_stone = _pal(palette, cache, "minecraft:stone")
    p_cobble = _pal(palette, cache, "minecraft:cobblestone")
    p_planks = _pal(palette, cache, "minecraft:stone_bricks")
    p_glass = _pal(palette, cache, "minecraft:glass")
    blocks: list[BlockEntry] = []
    mid = H - 4

    def put(x, y, z, p):
        blocks.append(BlockEntry(x, y, z, p))

    for z in range(D):
        for x in range(W):
            # deck
            put(x, mid, z, p_planks)
            # arch supports below deck: arch dips in middle
            dy = abs(x - (W - 1) // 2)
            for y in range(0, mid):
                if y <= (mid - 4 - dy) and (z in (0, D - 1) or z == D // 2):
                    put(x, y, z, p_stone if y < 2 else p_cobble)
    # railings + glass lamp posts every 5
    for x in range(0, W, 1):
        for z in (0, D - 1):
            put(x, mid + 1, z, p_cobble)
    for x in range(0, W, 5):
        put(x, mid + 2, 0, p_glass)
        put(x, mid + 2, D - 1, p_glass)
    layers = [Layer("deck", "سطح الجسر", mid - 1, mid + 2),
              Layer("arches", "الأقواس", 0, mid - 2)]
    return Design(
        name="Arch Bridge 21×9×7",
        description="جسر حجري بأقواس متماثلة مع أعمدة زجاجية. مثال هندسي لاختبار الدوران والطبقات.",
        dimensions=(W, H, D), palette=palette, blocks=dedupe(blocks), layers=layers,
        metadata={"generator": "scripts/gen_examples.py", "source": "schematic3d"},
    )


def main(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    designs = {"cottage-12x8x12": cottage(), "tower-9x18x9": tower(),
               "arch-bridge-21x9x7": bridge()}
    for stem, d in designs.items():
        (out_dir / f"{stem}.json").write_text(d.to_json(pretty=True), encoding="utf-8")
        write_mcstructure(d, out_dir / f"{stem}.mcstructure")
        print(f"wrote {stem}.json ({d.block_count} blocks) + .mcstructure")

    # broken fixtures -------------------------------------------------------
    good = json.loads((out_dir / "cottage-12x8x12.json").read_text(encoding="utf-8"))
    b1 = dict(good); b1["schemaVersion"] = 99
    (out_dir / "broken-bad-version.json").write_text(json.dumps(b1), encoding="utf-8")
    b2 = json.loads(json.dumps(good))
    b2["blocks"].append({"x": 999, "y": 0, "z": 0, "paletteIndex": 0})
    (out_dir / "broken-out-of-bounds.json").write_text(json.dumps(b2), encoding="utf-8")
    b3 = json.loads(json.dumps(good))
    b3["blocks"].append(dict(b3["blocks"][0]))
    (out_dir / "broken-duplicate.json").write_text(json.dumps(b3), encoding="utf-8")
    b4 = json.loads(json.dumps(good))
    b4["blocks"][0]["paletteIndex"] = 999
    (out_dir / "broken-bad-palette-index.json").write_text(json.dumps(b4), encoding="utf-8")
    (out_dir / "broken-truncated.json").write_text('{"format": "schematic3d-build", ', encoding="utf-8")
    print("wrote broken fixtures")


if __name__ == "__main__":
    main(ROOT / "examples")
