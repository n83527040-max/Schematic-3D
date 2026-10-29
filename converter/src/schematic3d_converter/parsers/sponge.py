"""Legacy MCEdit `.schematic` reader (big-endian, gzip NBT).

Format: Width/Height/Length (shorts), Materials (list of "old:name" strings),
Blocks (byte array; negative bytes read unsigned via +256), AddBlocks
(nibble extra for ids > 255). Order: same ZYX as mcstructure:
index = (x * Height + y) * Length + z   [per sponge docs "left→right,
bottom→top, north→south" with Width on X].

Numeric ids are mapped through a curated legacy table; unmapped ids are
reported. This parser intentionally supports the *classic building* subset —
it is not a general MCEdit import.
"""
from __future__ import annotations

from pathlib import Path

from ..models import BlockEntry, Design, Layer, PaletteEntry
from ..nbt import NbtError, read_nbt
from ..validate import ValidationReport

# Curated legacy-id → Bedrock id (the common building vocabulary).
LEGACY_IDS: dict[int, str] = {
    0: "minecraft:air",
    1: "minecraft:stone", 2: "minecraft:grass", 3: "minecraft:dirt",
    4: "minecraft:cobblestone", 5: "minecraft:oak_planks",
    6: "minecraft:oak_sapling", 7: "minecraft:bedrock",
    8: "minecraft:water", 9: "minecraft:water", 10: "minecraft:lava",
    11: "minecraft:lava", 12: "minecraft:sand", 13: "minecraft:gravel",
    14: "minecraft:gold_ore", 15: "minecraft:iron_ore", 16: "minecraft:coal_ore",
    17: "minecraft:oak_log", 18: "minecraft:oak_leaves",
    19: "minecraft:sponge", 20: "minecraft:glass",
    21: "minecraft:lapis_ore", 22: "minecraft:lapis_block",
    23: "minecraft:dispenser", 24: "minecraft:sandstone",
    25: "minecraft:noteblock", 27: "minecraft:golden_rail",
    28: "minecraft:sticky_piston", 29: "minecraft:web", 30: "minecraft:shrub",
    31: "minecraft:tallgrass", 32: "minecraft:deadbush", 33: "minecraft:piston",
    35: "minecraft:wool", 37: "minecraft:red_flower", 38: "minecraft:yellow_flower",
    39: "minecraft:brown_mushroom", 40: "minecraft:red_mushroom",
    41: "minecraft:gold_block", 42: "minecraft:iron_block",
    43: "minecraft:double_stone_slab", 44: "minecraft:stone_block_slab",
    45: "minecraft:brick_block", 46: "minecraft:tnt",
    47: "minecraft:bookshelf", 48: "minecraft:mossy_cobblestone",
    49: "minecraft:obsidian", 50: "minecraft:torch",
    51: "minecraft:fire", 52: "minecraft:spawner",
    53: "minecraft:oak_stairs", 54: "minecraft:chest",
    55: "minecraft:diamond_ore", 56: "minecraft:diamond_block",
    57: "minecraft:crafting_table", 58: "minecraft:farmland",
    59: "minecraft:wheat", 60: "minecraft:fence",
    61: "minecraft:coal_ore", 63: "minecraft:fence_gate",
    65: "minecraft:ladder", 66: "minecraft:rail",
    67: "minecraft:cobblestone_wall", 69: "minecraft:stone_pressure_plate",
    72: "minecraft:oak_button", 73: "minecraft:redstone_ore",
    75: "minecraft:unlit_redstone_torch", 76: "minecraft:redstone_torch",
    77: "minecraft:stone_button", 78: "minecraft:snow_layer",
    79: "minecraft:ice", 80: "minecraft:snow", 81: "minecraft:cactus",
    82: "minecraft:clay", 83: "minecraft:reeds", 84: "minecraft:jukebox",
    85: "minecraft:fence", 86: "minecraft:pumpkin", 87: "minecraft:netherrack",
    88: "minecraft:soul_sand", 89: "minecraft:glowstone",
    90: "minecraft:portal", 91: "minecraft:lit_pumpkin",
    95: "minecraft:stained_glass", 96: "minecraft:trapdoor",
    97: "minecraft:monster_egg", 98: "minecraft:stonebrick",
    100: "minecraft:brown_mushroom_block", 101: "minecraft:red_mushroom_block",
    102: "minecraft:iron_bars", 103: "minecraft:melon_block",
    106: "minecraft:pumpkin_stem", 107: "minecraft:melon_stem",
    108: "minecraft:fence_gate", 109: "minecraft:brick_stairs",
    110: "minecraft:stone_brick_stairs", 112: "minecraft:nether_brick",
    113: "minecraft:nether_brick_fence", 114: "minecraft:nether_brick_stairs",
    121: "minecraft:end_stone", 122: "minecraft:dragon_egg",
    123: "minecraft:redstone_lamp", 124: "minecraft:lit_redstone_lamp",
    125: "minecraft:double_wooden_slab", 126: "minecraft:wooden_slab",
    129: "minecraft:cocoa", 133: "minecraft:emerald_ore",
    134: "minecraft:ender_chest", 136: "minecraft:command_block",
    137: "minecraft:quartz_block", 138: "minecraft:quartz_stairs",
    139: "minecraft:activator_rail", 143: "minecraft:oak_wood_stairs? no",
    152: "minecraft:gold_block_2? no",
    155: "minecraft:hay_block", 156: "minecraft:carpet",
    157: "minecraft:hardened_clay", 158: "minecraft:stained_hardened_clay",
    159: "minecraft:coal_block", 161: "minecraft:acacia_leaves",
    162: "minecraft:log2", 163: "minecraft:acacia_fence",
    164: "minecraft:acacia_stairs", 165: "minecraft:brick_wall",
    167: "minecraft:iron_trapdoor", 170: "minecraft:flower_pot",
    171: "minecraft:beacon", 172: "minecraft:stone_slab3? no",
    173: "minecraft:daylight_detector", 175: "minecraft:redstone_block",
    176: "minecraft:quartz_ore", 178: "minecraft:hopper",
    179: "minecraft:packed_ice", 180: "minecraft:tripwire_hook",
    183: "minecraft:daylight_detector_inverted",
    185: "minecraft:spruce_stairs", 186: "minecraft:birch_stairs",
    187: "minecraft:jungle_stairs", 188: "minecraft:command_block",
    189: "minecraft:unpowered_repeater", 190: "minecraft:repeater",
    191: "minecraft:unpowered_comparator", 192: "minecraft:comparator",
    193: "minecraft:structure_block", 195: "minecraft:grass_path? no",
    196: "minecraft:light_weighted_pressure_plate",
    197: "minecraft:heavy_weighted_pressure_plate",
    198: "minecraft:spruce_fence_gate", 199: "minecraft:birch_fence_gate",
    200: "minecraft:jungle_fence_gate", 201: "minecraft:dark_oak_fence_gate",
    202: "minecraft:acacia_fence_gate",
    203: "minecraft:spruce_fence", 204: "minecraft:birch_fence",
    205: "minecraft:jungle_fence", 206: "minecraft:dark_oak_fence",
    207: "minecraft:acacia_fence",
    208: "minecraft:spruce_door", 209: "minecraft:birch_door",
    210: "minecraft:jungle_door", 211: "minecraft:acacia_door",
    212: "minecraft:dark_oak_door",
    213: "minecraft:smoker", 214: "minecraft:blast_furnace",
    217: "minecraft:grindstone", 218: "minecraft:smithing_table? legacy no",
    222: "minecraft:chain? no",
    235: "minecraft:white_bed", 236: "minecraft:iron_bars_dup? no",
    248: "minecraft:beehive", 249: "minecraft:bamboo",
    250: "minecraft:lantern", 251: "minecraft:campfire",
    252: "minecraft:soul_lantern? no", 255: "minecraft:stone? no",
    -1: None,  # sentinel removed at load
}

LEGACY_IDS = {k: v for k, v in LEGACY_IDS.items()
              if v is not None and "? no" not in v}


class SchematicError(Exception):
    pass


def parse_file(path: Path):
    return parse_bytes(path.read_bytes(), source_name=path.stem)


def parse_bytes(data: bytes, *, source_name: str = "schematic"):
    rep = ValidationReport()
    try:
        _, root = read_nbt(data, little_endian=False)
    except NbtError as exc:
        raise SchematicError(f"malformed schematic NBT: {exc}") from exc

    def num(v):
        return int(v)

    for key in ("Width", "Height", "Length"):
        if key not in root:
            raise SchematicError(f"missing {key} tag")
    w, h, l = num(root["Width"]), num(root["Height"]), num(root["Length"])
    if not all(1 <= v <= 512 for v in (w, h, l)):
        raise SchematicError(f"dimensions {w}x{h}x{l} outside supported 1..512")

    blocks_raw = root.get("Blocks")
    if not isinstance(blocks_raw, (list, tuple)) or len(blocks_raw) != w * h * l:
        raise SchematicError("Blocks array missing or wrong length")
    add_blocks = root.get("AddBlocks")
    if isinstance(add_blocks, (list, tuple)):
        # unpack nibbles: low nibble on even index, high on odd
        add = [0] * (w * h * l)
        for i, v in enumerate(add_blocks):
            v &= 0xFF
            idx0 = i * 2
            if idx0 < len(add):
                add[idx0] = v & 0x0F
            if idx0 + 1 < len(add):
                add[idx0 + 1] = (v >> 4) & 0x0F
    else:
        add = None

    materials = root.get("Materials", [])
    if isinstance(materials, list) and materials and isinstance(materials[0], str):
        mats = [m[4:] if m.startswith("old:") else m for m in materials]
    else:
        mats = None

    palette: dict[PaletteEntry, int] = {}
    palette_list: list[PaletteEntry] = []
    out_blocks: list[BlockEntry] = []
    unmapped: dict[str, int] = {}

    for i, low in enumerate(blocks_raw):
        bid = (low & 0xFF) | (((add[i] & 0xF) if add else 0) << 8)
        if bid == 0:
            continue
        name: str | None = None
        if mats and bid < len(mats):
            name = mats[bid]
            if name in ("Air", "air"):
                continue
        if name is not None:
            # map legacy textual name to bedrock id heuristics
            mapped = _LEGACY_NAME_MAP.get(name.lower())
            if mapped is None:
                unmapped[name] = unmapped.get(name, 0) + 1
                continue
            pe = PaletteEntry.make(mapped, {})
        else:
            mapped = LEGACY_IDS.get(bid)
            if mapped is None:
                unmapped[str(bid)] = unmapped.get(str(bid), 0) + 1
                continue
            pe = PaletteEntry.make(mapped, {})
        if pe not in palette:
            palette[pe] = len(palette_list)
            palette_list.append(pe)
        # MCEdit order: index = (y * Length + z) * Width + x
        y = i // (l * w)
        rem = i % (l * w)
        z = rem // w
        x = rem % w
        out_blocks.append(BlockEntry(x, y, z, palette[pe]))

    for name, cnt in sorted(unmapped.items(), key=lambda kv: -kv[1])[:32]:
        rep.warning("schematic.unsupported",
                    f"legacy id {name!r} ×{cnt} has no Bedrock mapping; blocks dropped")
    if not out_blocks:
        raise SchematicError("no blocks left after mapping")

    design = Design(
        name=source_name, description="Imported from legacy .schematic",
        dimensions=(w, h, l), palette=palette_list, blocks=out_blocks,
        layers=[Layer("all", "All layers", 0, h - 1)],
        metadata={"source": "schematic", "generator": "schematic3d_converter",
                  "unsupportedFeatures": [f"legacy:{k}" for k in unmapped][:64]},
    )
    return design, rep


_LEGACY_NAME_MAP = {
    "stone": "minecraft:stone", "grass": "minecraft:grass",
    "dirt": "minecraft:dirt", "cobblestone": "minecraft:cobblestone",
    "planks": "minecraft:oak_planks", "bedrock": "minecraft:bedrock",
    "water": "minecraft:water", "flowing_water": "minecraft:water",
    "lava": "minecraft:lava", "flowing_lava": "minecraft:lava",
    "sand": "minecraft:sand", "gravel": "minecraft:gravel",
    "gold_ore": "minecraft:gold_ore", "iron_ore": "minecraft:iron_ore",
    "coal_ore": "minecraft:coal_ore", "log": "minecraft:oak_log",
    "leaves": "minecraft:oak_leaves", "sponge": "minecraft:sponge",
    "glass": "minecraft:glass", "lapis_ore": "minecraft:lapis_ore",
    "lapis_block": "minecraft:lapis_block",
    "sandstone": "minecraft:sandstone", "noteblock": "minecraft:noteblock",
    "white_wool": "minecraft:white_wool", "wool": "minecraft:wool",
    "brick_block": "minecraft:bricks", "tnt": "minecraft:tnt",
    "bookshelf": "minecraft:bookshelf",
    "mossy_cobblestone": "minecraft:mossy_cobblestone",
    "obsidian": "minecraft:obsidian", "torch": "minecraft:torch",
    "oak_stairs": "minecraft:oak_stairs", "chest": "minecraft:chest",
    "diamond_ore": "minecraft:diamond_ore",
    "diamond_block": "minecraft:diamond_block",
    "crafting_table": "minecraft:crafting_table",
    "farmland": "minecraft:farmland", "fence": "minecraft:oak_fence",
    "glowstone": "minecraft:glowstone", "ice": "minecraft:ice",
    "snow": "minecraft:snow", "snow_layer": "minecraft:snow_layer",
    "cactus": "minecraft:cactus", "clay": "minecraft:clay",
    "reeds": "minecraft:sugar_cane", "jukebox": "minecraft:jukebox",
    "fence_gate": "minecraft:oak_fence_gate",
    "netherrack": "minecraft:netherrack",
    "soul_sand": "minecraft:soul_sand", "melon_block": "minecraft:melon_block",
    "brick_stairs": "minecraft:brick_stairs",
    "stone_brick_stairs": "minecraft:stone_brick_stairs",
    "nether_brick": "minecraft:nether_brick",
    "nether_brick_stairs": "minecraft:nether_brick_stairs",
    "end_stone": "minecraft:end_stone",
    "redstone_lamp": "minecraft:redstone_lamp",
    "wooden_slab": "minecraft:wooden_slab",
    "emerald_ore": "minecraft:emerald_ore", "emerald_block": "minecraft:emerald_block",
    "gold_block": "minecraft:gold_block", "iron_block": "minecraft:iron_block",
    "quartz_block": "minecraft:quartz_block",
    "quartz_stairs": "minecraft:quartz_stairs",
    "hay_block": "minecraft:hay_block", "hardened_clay": "minecraft:terracotta",
    "coal_block": "minecraft:coal_block",
    "packed_ice": "minecraft:packed_ice", "iron_bars": "minecraft:iron_bars",
    "redstone_block": "minecraft:redstone_block",
    "hopper": "minecraft:hopper", "ladder": "minecraft:ladder",
    "stonebrick": "minecraft:stone_bricks",
    "stone_brick_slab": "minecraft:stone_brick_slab",
    "smooth_slab": "minecraft:smooth_stone_slab",
    "stone_slab": "minecraft:stone_block_slab",
    "carpet": "minecraft:carpet", "flower_rose": "minecraft:red_flower",
    "flower_tulip_red": "minecraft:red_tulip", "yellow_flower": "minecraft:yellow_flower",
    "double_plant": "minecraft:double_plant", "tall_grass": "minecraft:tallgrass",
    "large_fern": "minecraft:large_fern", "fern": "minecraft:fern",
    "cobblestone_wall": "minecraft:cobblestone_wall",
    "stone_stairs": "minecraft:stone_stairs",
}
