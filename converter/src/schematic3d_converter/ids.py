"""Known Bedrock block ids used for *static* validation.

Design contract (docs/02_formats.md):
- The list is a conservative snapshot of block ids that `/setblock` on
  Bedrock 1.26.x accepts verbatim. It is NOT the full registry.
- An id missing from the list yields a WARNING ("unverified id") and is
  still exported; the in-game placement attempt is the final validator and
  its failure is surfaced in the build report.
- Ids that exist only as state-carrying families (`planks[wood_type]`,
  `stained_glass[color]`, …) are listed as the family id; flattened color
  variants that Bedrock definitely ships (wool, concrete, terracotta,
  concrete_powder) are listed individually.
"""
from __future__ import annotations

import json
from pathlib import Path

_DYE_COLORS = [
    "white", "orange", "magenta", "light_blue", "yellow", "lime", "pink",
    "gray", "light_gray", "cyan", "purple", "blue", "brown", "green", "red",
    "black",
]


def _colored(suffix: str) -> list[str]:
    return [f"{c}_{suffix}" for c in _DYE_COLORS]


_WOODS = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak"]
_EXOTIC = ["mangrove", "cherry", "crimson", "warped", "bamboo"]

KNOWN_BEDROCK_IDS: frozenset[str] = frozenset(
    {
        # terrain / stone family
        "air", "stone", "granite", "polished_granite", "andesite",
        "polished_andesite", "diorite", "polished_diorite", "deepslate",
        "cobbled_deepslate", "polished_deepslate", "deepslate_bricks",
        "deepslate_tiles", "chiseled_deepslate", "tuff", "polished_tuff",
        "tuff_bricks", "chiseled_tuff", "calcite", "dripstone_block",
        "pointed_dripstone", "grass", "dirt", "coarse_dirt", "rooted_dirt",
        "podzol", "mycelium", "mud", "packed_mud", "clay", "sand",
        "red_sand", "gravel", "snow", "ice", "packed_ice", "blue_ice",
        "obsidian", "crying_obsidian", "bedrock", "barrier", "structure_void",
        "structure_block",         "end_stone", "end_stone_bricks", "purpur_block", "purpur_pillar",
        "smooth_stone", "cobblestone", "mossy_cobblestone", "stone_bricks",
        "mossy_stone_bricks", "cracked_stone_bricks", "chiseled_stone_bricks",
        "sandstone", "smooth_sandstone", "chiseled_sandstone", "cut_sandstone",
        "red_sandstone", "smooth_red_sandstone", "bricks", "moss_block",
        "moss_carpet", "pale_moss_block", "pale_moss_carpet", "sculk",
        "sculk_catalyst", "sculk_sensor", "sculk_shrieker", "sculk_vein",
        # light & utility
        "glowstone", "shroomlight", "sea_lantern", "torch", "soul_torch",
        "lantern", "soul_lantern", "candle", "campfire", "soul_campfire",
        "end_rod", "beacon", "conduit", "lodestone", "respawn_anchor",
        "scaffolding", "anvil", "grindstone", "smithing_table",
        "stonecutter_block", "stonecutter2", "crafting_table",
        "enchanting_table", "bookshelf", "chiseled_bookshelf", "furnace",
        "blast_furnace", "smoker", "chest", "barrel", "trapped_chest",
        "ender_chest", "composter", "bell", "chain", "iron_bars",
        "skull", "flower_pot", "decorated_pot", "item_frame",
        "glow_item_frame", "frame",
        # redstone & tech
        "redstone_block", "redstone_wire", "redstone_ore", "redstone_torch",
        "repeater", "comparator", "lever", "daylight_detector",
        "daylight_detector_inverted", "observer", "piston", "sticky_piston",
        "piston_arm_collision", "piston_arm_nohead", "dispenser", "dropper",
        "hopper", "tnt", "noteblock", "jukebox", "target", "light_block_0",
        # functional/misc vanilla
        "water", "lava", "web", "sculk", "slime", "honey_block",
        "honeycomb_block", "sponge", "wet_sponge", "hay_block", "bone_block",
        "snow_layer", "carpet", "stained_glass", "stained_glass_pane",
        "glass", "glass_pane", "tinted_glass", "sea_pickle",
        "magma", "nether_wart_block", "warped_wart_block",
        "netherrack", "nether_gold_ore", "nether_quartz_ore",
        "soul_sand", "soul_soil", "basalt", "polished_basalt",
        "smooth_basalt", "blackstone", "gilded_blackstone",
        "polished_blackstone", "polished_blackstone_bricks",
        "chiseled_polished_blackstone", "cracked_polished_blackstone_bricks",
        "ancient_debris", "nether_brick", "red_nether_brick",
        "nether_wart", "crimson_nylium", "warped_nylium", "nether_sprouts",
        "crimson_roots", "warped_roots", "shroomlight", "weeping_vines",
        "twisting_vines",
        # ores & mineral blocks
        "coal_ore", "iron_ore", "copper_ore", "gold_ore", "lapis_ore",
        "diamond_ore", "emerald_ore", "deepslate_coal_ore",
        "deepslate_iron_ore", "deepslate_copper_ore", "deepslate_gold_ore",
        "deepslate_lapis_ore", "deepslate_diamond_ore",
        "deepslate_emerald_ore", "coal_block", "iron_block", "copper_block",
        "gold_block", "diamond_block", "emerald_block", "lapis_block",
        "raw_iron_block", "raw_copper_block", "raw_gold_block",
        "netherite_block", "quartz_block", "quartz_bricks", "quartz_pillar",
        "chiseled_quartz_block", "smooth_quartz", "amethyst_block",
        "budding_amethyst", "amethyst_cluster", "large_amethyst_bud",
        "medium_amethyst_bud", "small_amethyst_bud",
        "copper_grate", "cut_copper", "chiseled_copper", "exposed_copper",
        "exposed_cut_copper", "exposed_chiseled_copper",
        "exposed_copper_grate", "weathered_copper", "weathered_cut_copper",
        "weathered_chiseled_copper", "weathered_copper_grate",
        "oxidized_copper", "oxidized_cut_copper", "oxidized_chiseled_copper",
        "oxidized_copper_grate", "lightning_rod", "copper_bulb",
        # plants
        "sapling", "short_grass", "tallgrass", "fern",
        "large_fern", "double_plant", "deadbush", "cactus", "melon_block",
        "melon_stem", "pumpkin", "carved_pumpkin", "lit_pumpkin",
        "pumpkin_stem", "bamboo", "bamboo_plant_block", "sugar_cane",
        "cocoa", "vine", "glow_lichen", "coral_block", "coral", "coral_fan",
        "coral_wall_fan", "seagrass", "kelp", "kelp_plant", "lily_pad",
        "big_dripleaf", "big_dripleaf_stem", "small_dripleaf",
        "hanging_roots", "leaf_litter", "spore_blossom", "pitcher_plant",
        "torchflower", "red_flower", "yellow_flower", "blue_orchid",
        "allium", "azure_bluet", "red_tulip", "orange_tulip",
        "white_tulip", "pink_tulip", "oxeye_daisy", "cornflower",
        "lily_of_the_valley", "wither_rose", "torchflower_crop",
        "pitcher_crop", "pink_petals", "wildflowers",         "mangrove_propagule", "coral_fan_dead", "sea_pickle",
        "waterlily",
        # families with states (legacy names Bedrock still accepts)
        "planks", "planks2", "log", "log2", "wood", "wood2",
        "leaves", "leaves2", "fence", "fence_gate", "wooden_door", "trapdoor",
        "wooden_button", "wooden_pressure_plate", "standing_banner",
        "wall_banner", "standing_sign", "wall_sign", "bed", "iron_door",
        "acacia_door", "birch_door", "dark_oak_door", "jungle_door",
        "spruce_door", "oak_door", "mangrove_door", "cherry_door",
        "crimson_door", "warped_door", "bamboo_door",
        "iron_trapdoor", "acacia_trapdoor", "birch_trapdoor",
        "dark_oak_trapdoor", "jungle_trapdoor", "spruce_trapdoor",
        "oak_trapdoor", "mangrove_trapdoor", "cherry_trapdoor",
        "crimson_trapdoor", "warped_trapdoor", "bamboo_trapdoor",
        "stone_brick_stairs", "stone_block_slab", "stone_block_slab1",
        "stone_block_slab2", "stone_block_slab3", "stone_block_slab4",
        "brick_stairs", "nether_brick_stairs", "sandstone_stairs",
        "quartz_stairs", "purpur_stairs", "acacia_stairs", "birch_stairs",
        "dark_oak_stairs", "jungle_stairs", "oak_stairs", "spruce_stairs",
        "mangrove_stairs", "cherry_stairs", "crimson_stairs",
        "warped_stairs", "bamboo_stairs", "mossy_stone_brick_stairs",
        "smooth_sandstone_stairs", "red_sandstone_stairs",
        "smooth_red_sandstone_stairs", "end_stone_brick_stairs",
        "prismarine_stairs", "dark_prismarine_stairs",
        "prismarine_bricks_stairs", "polished_granite_stairs",
        "andesite_stairs", "diorite_stairs", "granite_stairs",
        "cobblestone_stairs", "mossy_cobblestone_stairs",
        "blackstone_stairs", "polished_blackstone_stairs",
        "polished_blackstone_brick_stairs", "deepslate_brick_stairs",
        "deepslate_tile_stairs", "polished_deepslate_stairs",
        "cobbled_deepslate_stairs", "tuff_stairs", "polished_tuff_stairs",
        "tuff_brick_stairs", "exposed_cut_copper_stairs",
        "weathered_cut_copper_stairs", "oxidized_cut_copper_stairs",
        "cut_copper_stairs", "wall_coral_fan_dead",
        "cobblestone_wall", "mossy_cobblestone_wall", "brick_wall",
        "stone_brick_wall", "granite_wall", "diorite_wall", "andesite_wall",
        "sandstone_wall", "nether_brick_wall", "red_nether_brick_wall",
        "end_stone_brick_wall", "prismarine_wall", "mossy_stone_brick_wall",
        "blackstone_wall", "polished_blackstone_wall",
        "polished_blackstone_brick_wall", "deepslate_tile_wall",
        "deepslate_brick_wall", "cobbled_deepslate_wall",
        "polished_deepslate_wall", "mangrove_wall", "bamboo_wall",
        "cherry_wall", "crimson_wall", "warped_wall", "tuff_wall",
        "polished_tuff_wall", "tuff_brick_wall",
        "stone_stairs", "smooth_quartz_stairs", "basalt_stairs",
        "polished_basalt_stairs", "smooth_basalt_stairs",
        # prismarine & ocean
        "prismarine", "prismarine_bricks", "dark_prismarine",
        # colored flattened families Bedrock definitely ships
        *set(_colored("wool")),
        *set(_colored("carpet")),
        *set(_colored("concrete")),
        *set(_colored("concrete_powder")),
        *set(_colored("terracotta")),
        *set(_colored("glazed_terracotta")),
        *set(_colored("shulker_box")),
        *set(_colored("candle")),
        *set(_colored("bed")),
        *set(_colored("banner")),
        "hardened_clay", "stained_hardened_clay",
        # coral variants
        "coral_block", "coral_fan_dead", "bubble_column",
        # beds & doors simplified aliases
        "white_bed", "red_bed", "blue_bed", "green_bed",
        # internal addon blocks (registered by Schematic 3D Builder BP)
        *[f"s3d:{n}" for n in
          ["ghost_white", "ghost_gray", "ghost_black", "ghost_wood", "ghost_stone",
           "ghost_sand", "ghost_glass", "ghost_red", "ghost_green", "ghost_blue",
           "ghost_metal", "ghost_glow", "highlight", "origin_marker"]],
    }
    - {"void_block? no", "leafy_cactus? no"}
)


KNOWN_BEDROCK_FULL = frozenset(f"minecraft:{x}" for x in KNOWN_BEDROCK_IDS) | \
    frozenset(x for x in KNOWN_BEDROCK_IDS if ":" in x)

# Java (Flattening, 1.20+ ids) name -> Bedrock id for the common building
# vocabulary. Anything not listed is reported as an explicit unsupported
# conversion entry (never silently guessed).
JAVA_TO_BEDROCK: dict[str, str] = {
    "grass_block": "minecraft:grass",
    "dirt_path": "minecraft:grass_path",
    "watermelon": "minecraft:melon_block",
    "melon": "minecraft:melon_block",
    "bookshelf": "minecraft:bookshelf",
    "glowstone": "minecraft:glowstone",
    "nether_bricks": "minecraft:nether_brick",
    "red_nether_bricks": "minecraft:red_nether_brick",
    "slime_block": "minecraft:slime",
    "cobweb": "minecraft:web",
    "furnace": "minecraft:furnace",
    "blast_furnace": "minecraft:blast_furnace",
    "smoker": "minecraft:smoker",
    "stonecutter": "minecraft:stonecutter_block",
    "note_block": "minecraft:noteblock",
    "magma_block": "minecraft:magma",
    "end_stone_bricks": "minecraft:end_stone_bricks",
    "purpur_stairs": "minecraft:purpur_stairs",
    "cobblestone_wall": "minecraft:cobblestone_wall",
    "sandstone_wall": "minecraft:sandstone_wall",
    "stone_brick_wall": "minecraft:stone_brick_wall",
    "mossy_stone_brick_wall": "minecraft:mossy_stone_brick_wall",
    "granite_wall": "minecraft:granite_wall",
    "diorite_wall": "minecraft:diorite_wall",
    "andesite_wall": "minecraft:andesite_wall",
    "brick_wall": "minecraft:brick_wall",
    "prismarine_wall": "minecraft:prismarine_wall",
    "red_sandstone_wall": "minecraft:sandstone_wall",
    "polished_granite_stairs": "minecraft:polished_granite_stairs",
    "amethyst_block": "minecraft:amethyst_block",
    "budding_amethyst": "minecraft:budding_amethyst",
    "calcite": "minecraft:calcite",
    "tuff": "minecraft:tuff",
    "smooth_basalt": "minecraft:smooth_basalt",
    "dripstone_block": "minecraft:dripstone_block",
    "pointed_dripstone": "minecraft:pointed_dripstone",
    "rooted_dirt": "minecraft:rooted_dirt",
    "hanging_roots": "minecraft:hanging_roots",
    "powder_snow_cauldron": "minecraft:cauldron",
    "sculk": "minecraft:sculk",
    "sculk_vein": "minecraft:sculk_vein",
    "sculk_catalyst": "minecraft:sculk_catalyst",
    "sculk_sensor": "minecraft:sculk_sensor",
    "sculk_shrieker": "minecraft:sculk_shrieker",
    "deepslate": "minecraft:deepslate",
    "cobbled_deepslate": "minecraft:cobbled_deepslate",
    "polished_deepslate": "minecraft:polished_deepslate",
    "deepslate_bricks": "minecraft:deepslate_bricks",
    "deepslate_tiles": "minecraft:deepslate_tiles",
    "chiseled_deepslate": "minecraft:chiseled_deepslate",
    "tuff_bricks": "minecraft:tuff_bricks",
    "polished_tuff": "minecraft:polished_tuff",
    "chiseled_tuff": "minecraft:chiseled_tuff",
    "grass": "minecraft:short_grass",
    "vine": "minecraft:vine",
    "lily_pad": "minecraft:waterlily",
    "big_dripleaf": "minecraft:big_dripleaf",
    "small_dripleaf_block": "minecraft:small_dripleaf",
    "spore_blossom": "minecraft:spore_blossom",
    "azalea": "minecraft:red_flower",
    "flowering_azalea": "minecraft:red_flower",
    "mangrove_roots": "minecraft:mangrove_roots",
    "muddy_mangrove_roots": "minecraft:muddy_mangrove_roots",
    "reinforced_deepslate": "minecraft:deepslate",
}

# Per-color state->name helpers used by both .schematic (pre-flatten) and
# litematic conversion of the classic family blocks.
JAVA_FAMILY_TO_BEDROCK = {
    "planks": {
        "oak": "minecraft:oak_planks", "spruce": "minecraft:spruce_planks",
        "birch": "minecraft:birch_planks", "jungle": "minecraft:jungle_planks",
        "acacia": "minecraft:acacia_planks", "dark_oak": "minecraft:dark_oak_planks",
    },
    "log": {
        "oak": "minecraft:oak_log", "spruce": "minecraft:spruce_log",
        "birch": "minecraft:birch_log", "jungle": "minecraft:jungle_log",
        "acacia": "minecraft:acacia_log", "dark_oak": "minecraft:dark_oak_log",
    },
    "leaves": {
        "oak": "minecraft:oak_leaves", "spruce": "minecraft:spruce_leaves",
        "birch": "minecraft:birch_leaves", "jungle": "minecraft:jungle_leaves",
    },
    "leaves2": {
        "acacia": "minecraft:acacia_leaves", "dark_oak": "minecraft:dark_oak_leaves",
    },
    "fence": {
        "oak": "minecraft:oak_fence", "spruce": "minecraft:spruce_fence",
        "birch": "minecraft:birch_fence", "jungle": "minecraft:jungle_fence",
        "acacia": "minecraft:acacia_fence", "dark_oak": "minecraft:dark_oak_fence",
    },
    "stained_glass": {
        "white": "minecraft:white_stained_glass", "orange": "minecraft:orange_stained_glass",
        "magenta": "minecraft:magenta_stained_glass", "light_blue": "minecraft:light_blue_stained_glass",
        "yellow": "minecraft:yellow_stained_glass", "lime": "minecraft:lime_stained_glass",
        "pink": "minecraft:pink_stained_glass", "gray": "minecraft:gray_stained_glass",
        "silver": "minecraft:light_gray_stained_glass", "light_gray": "minecraft:light_gray_stained_glass",
        "cyan": "minecraft:cyan_stained_glass", "purple": "minecraft:purple_stained_glass",
        "blue": "minecraft:blue_stained_glass", "brown": "minecraft:brown_stained_glass",
        "green": "minecraft:green_stained_glass", "red": "minecraft:red_stained_glass",
        "black": "minecraft:black_stained_glass",
    },
    "stained_hardened_clay": {
        "white": "minecraft:white_terracotta", "orange": "minecraft:orange_terracotta",
        "magenta": "minecraft:magenta_terracotta", "light_blue": "minecraft:light_blue_terracotta",
        "yellow": "minecraft:yellow_terracotta", "lime": "minecraft:lime_terracotta",
        "pink": "minecraft:pink_terracotta", "gray": "minecraft:gray_terracotta",
        "silver": "minecraft:light_gray_terracotta", "light_gray": "minecraft:light_gray_terracotta",
        "cyan": "minecraft:cyan_terracotta", "purple": "minecraft:purple_terracotta",
        "blue": "minecraft:blue_terracotta", "brown": "minecraft:brown_terracotta",
        "green": "minecraft:green_terracotta", "red": "minecraft:red_terracotta",
        "black": "minecraft:black_terracotta",
    },
    "wool": {
        "white": "minecraft:white_wool", "orange": "minecraft:orange_wool",
        "magenta": "minecraft:magenta_wool", "light_blue": "minecraft:light_blue_wool",
        "yellow": "minecraft:yellow_wool", "lime": "minecraft:lime_wool",
        "pink": "minecraft:pink_wool", "gray": "minecraft:gray_wool",
        "silver": "minecraft:light_gray_wool", "light_gray": "minecraft:light_gray_wool",
        "cyan": "minecraft:cyan_wool", "purple": "minecraft:purple_wool",
        "blue": "minecraft:blue_wool", "brown": "minecraft:brown_wool",
        "green": "minecraft:green_wool", "red": "minecraft:red_wool",
        "black": "minecraft:black_wool",
    },
    "carpet": {
        "white": "minecraft:white_carpet", "orange": "minecraft:orange_carpet",
        "magenta": "minecraft:magenta_carpet", "light_blue": "minecraft:light_blue_carpet",
        "yellow": "minecraft:yellow_carpet", "lime": "minecraft:lime_carpet",
        "pink": "minecraft:pink_carpet", "gray": "minecraft:gray_carpet",
        "silver": "minecraft:light_gray_carpet", "light_gray": "minecraft:light_gray_carpet",
        "cyan": "minecraft:cyan_carpet", "purple": "minecraft:purple_carpet",
        "blue": "minecraft:blue_carpet", "brown": "minecraft:brown_carpet",
        "green": "minecraft:green_carpet", "red": "minecraft:red_carpet",
        "black": "minecraft:black_carpet",
    },
    "concrete": {
        "white": "minecraft:white_concrete", "orange": "minecraft:orange_concrete",
        "magenta": "minecraft:magenta_concrete", "light_blue": "minecraft:light_blue_concrete",
        "yellow": "minecraft:yellow_concrete", "lime": "minecraft:lime_concrete",
        "pink": "minecraft:pink_concrete", "gray": "minecraft:gray_concrete",
        "silver": "minecraft:light_gray_concrete", "light_gray": "minecraft:light_gray_concrete",
        "cyan": "minecraft:cyan_concrete", "purple": "minecraft:purple_concrete",
        "blue": "minecraft:blue_concrete", "brown": "minecraft:brown_concrete",
        "green": "minecraft:green_concrete", "red": "minecraft:red_concrete",
        "black": "minecraft:black_concrete",
    },
    "concrete_powder": {
        "white": "minecraft:white_concrete_powder", "orange": "minecraft:orange_concrete_powder",
        "magenta": "minecraft:magenta_concrete_powder", "light_blue": "minecraft:light_blue_concrete_powder",
        "yellow": "minecraft:yellow_concrete_powder", "lime": "minecraft:lime_concrete_powder",
        "pink": "minecraft:pink_concrete_powder", "gray": "minecraft:gray_concrete_powder",
        "silver": "minecraft:light_gray_concrete_powder", "light_gray": "minecraft:light_gray_concrete_powder",
        "cyan": "minecraft:cyan_concrete_powder", "purple": "minecraft:purple_concrete_powder",
        "blue": "minecraft:blue_concrete_powder", "brown": "minecraft:brown_concrete_powder",
        "green": "minecraft:green_concrete_powder", "red": "minecraft:red_concrete_powder",
        "black": "minecraft:black_concrete_powder",
    },
}


def check_id(bedrock_id: str) -> str:
    """Classify a bedrock namespaced id: 'known' | 'unknown' | 'invalid'."""
    if not isinstance(bedrock_id, str) or ":" not in bedrock_id:
        return "invalid"
    ns, name = bedrock_id.split(":", 1)
    if not ns or not name:
        return "invalid"
    if ns in ("minecraft", "s3d"):
        return "known" if bedrock_id in KNOWN_BEDROCK_FULL else "unknown"
    return "unknown"


def to_full_id(raw: str) -> str:
    """Add minecraft: namespace when absent."""
    raw = raw.strip()
    if ":" in raw:
        return raw
    return f"minecraft:{raw}"


def snapshot_json() -> dict:
    """Portable asset for the Flutter app / docs (same data, one source)."""
    return {
        "generator": "schematic3d_converter.ids",
        "schema": 1,
        "note": "Static validation snapshot for Bedrock ~26.40. In-game registry is authoritative.",
        "knownBedrockIds": sorted(KNOWN_BEDROCK_IDS),
        "javaToBedrock": JAVA_TO_BEDROCK,
        "javaFamilyToBedrock": JAVA_FAMILY_TO_BEDROCK,
    }


def write_snapshot(out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    p = out_dir / "block_catalog.json"
    p.write_text(json.dumps(snapshot_json(), ensure_ascii=False, indent=1),
                 encoding="utf-8")
    return p
