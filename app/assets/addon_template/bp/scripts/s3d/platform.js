// Thin adapter over @minecraft/server so core modules stay test-free of the
// game API. All game access goes through `host`.
import {
    world, system, BlockPermutation, ItemStack, GameMode,
} from "@minecraft/server";

export const TICKS_PER_SECOND = 30;

export const host = {
    world,
    system,

    dimensionFor(player) {
        return player.dimension ?? world.getDimension("overworld");
    },
    getBlock(dimensionOrName, x, y, z) {
        const dim = typeof dimensionOrName === "string"
            ? world.getDimension(dimensionOrName) : dimensionOrName;
        try { return dim.getBlock({ x, y, z }); } catch { return undefined; }
    },
    setBlock(dimensionOrName, x, y, z, blockId) {
        const dim = typeof dimensionOrName === "string"
            ? world.getDimension(dimensionOrName) : dimensionOrName;
        try {
            dim.setBlockType({ x, y, z }, blockId);
            return true;
        } catch {
            return false;
        }
    },
    resolvePermutation(id, states) {
        return BlockPermutation.resolve(id, states ?? {});
    },
    setBlockPermutation(dimension, x, y, z, permutation) {
        try {
            dimension.setBlockPermutation({ x, y, z }, permutation);
            return true;
        } catch {
            return false;
        }
    },
    spawnParticle(name, loc) {
        try { world.getDimension("overworld").spawnParticle(name, loc); }
        catch { /* particle not registered — non-fatal */ }
    },

    // inventory (count + optional consume) ------------------------------
    inventoryOf(player) {
        try {
            return player.getComponent("minecraft:inventory")?.container;
        } catch { return undefined; }
    },
    countInventory(player, idSet) {
        const map = new Map([...idSet].map((id) => [id, 0]));
        const inv = this.inventoryOf(player);
        if (!inv) return null; // API could not read inventory → "unavailable"
        for (let slot = 0; slot < inv.size; slot++) {
            let st;
            try { st = inv.getItem(slot); } catch { continue; }
            if (!st) continue;
            if (map.has(st.typeId)) map.set(st.typeId, map.get(st.typeId) + st.amount);
        }
        return map;
    },
    consumeFromInventory(player, id, n) {
        const inv = this.inventoryOf(player);
        if (!inv) return 0;
        let left = n;
        for (let slot = 0; slot < inv.size && left > 0; slot++) {
            let st;
            try { st = inv.getItem(slot); } catch { continue; }
            if (!st || st.typeId !== id) continue;
            const take = Math.min(st.amount, left);
            left -= take;
            try {
                if (take >= st.amount) inv.setItem(slot, undefined);
                else { st.amount -= take; inv.setItem(slot, st); }
            } catch { return n - left; }
        }
        return n - left;
    },
    giveItem(player, id, amount = 1) {
        const inv = this.inventoryOf(player);
        if (!inv) return false;
        try {
            const leftover = inv.addItem(new ItemStack(id, amount));
            return leftover === undefined;
        } catch { return false; }
    },
    hasItem(player, id) {
        const inv = this.inventoryOf(player);
        if (!inv) return 0;
        try {
            const idx = inv.find(new ItemStack(id, 1));
            if (idx === undefined) return 0;
            return inv.getItem(idx)?.amount ?? 0;
        } catch { return 0; }
    },
    isCreative(player) {
        try { return player.getGameMode() === GameMode.creative; }
        catch { return false; }
    },

    // targeting ------------------------------------------------------------
    targetedBlock(player, maxDistance = 64) {
        try {
            const dim = player.dimension ?? world.getDimension("overworld");
            const eye = player.getHeadLocation();
            const dir = player.getEyeViewDirection?.() ?? player.getViewDirection();
            const hit = dim.getBlockFromRay(eye, dir, { maxDistance, includeLiquidBlocks: false, passThroughBlocks: false });
            if (hit) return hit.block;
            return undefined;
        } catch { return undefined; }
    },

    // messaging ------------------------------------------------------------
    notify(player, text) {
        try { player.sendMessage(text); } catch { /* ignore */ }
    },
    actionBar(player, text) {
        try {
            const dim = player.dimension ?? world.getDimension("overworld");
            dim.runCommand(`title "${player.name}" actionbar ${JSON.stringify(text)}`);
        } catch {
            this.notify(player, text);
        }
    },
    runJob(gen) { return system.runJob(gen); },
    clearRun(id) { try { system.clearRun(id); } catch { /* ignore */ } },
};
