#!/usr/bin/env node
// Generates shared golden vectors for the tint mapping so the add-on and the
// Flutter app stay provably in sync (app test loads the same JSON).
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ghostTintFor } from "../behavior_pack/scripts/s3d/core/tint.js";

const IDS = [
    "minecraft:stone", "minecraft:cobblestone", "minecraft:deepslate_bricks",
    "minecraft:oak_planks", "minecraft:spruce_log", "minecraft:birch_leaves",
    "minecraft:glass", "minecraft:tinted_glass", "minecraft:white_concrete",
    "minecraft:red_wool", "minecraft:light_blue_terracotta",
    "minecraft:sand", "minecraft:sandstone", "minecraft:gravel",
    "minecraft:obsidian", "minecraft:blackstone", "minecraft:glowstone",
    "minecraft:shroomlight", "minecraft:sea_lantern", "minecraft:torch",
    "minecraft:iron_bars", "minecraft:gold_block", "minecraft:copper_block",
    "minecraft:diamond_block", "minecraft:emerald_block", "minecraft:lapis_block",
    "minecraft:water", "minecraft:ice", "minecraft:snow", "minecraft:bricks",
    "minecraft:oak_stairs", "minecraft:bookshelf", "minecraft:crafting_table",
    "minecraft:moss_block", "minecraft:vine", "minecraft:nether_bricks",
    "minecraft:crimson_stem", "minecraft:warped_wart_block", "minecraft:prismarine",
    "minecraft:terracotta", "minecraft:hay_block", "minecraft:bone_block",
    "minecraft:end_stone", "minecraft:purpur_block", "minecraft:quartz_bricks",
    "minecraft:magma", "minecraft:soul_sand", "minecraft:redstone_block",
    "minecraft:air", "minecraft:structure_void",
];

const out = IDS.map((id) => ({ id, tint: ghostTintFor(id) }));
const here = dirname(fileURLToPath(import.meta.url));
const target = join(here, "..", "shared", "tint_vectors.json");
writeFileSync(target, JSON.stringify(out, null, 1) + "\n");
// second copy for the flutter app assets/test dir
const appCopy = join(here, "..", "..", "app", "assets", "generated", "tint_vectors.json");
try { writeFileSync(appCopy, JSON.stringify(out) + "\n"); }
catch { /* app dir may not exist yet */ }
console.log("wrote", target, "with", out.length, "vectors");
