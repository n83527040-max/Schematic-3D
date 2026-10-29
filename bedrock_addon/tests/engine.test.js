// Engine tests against a fake host (dimension simulation). This validates
// real control flow: budgeting, fallback placement, failure reporting,
// pause/resume, inventory gating, manual validation. It does NOT prove
// behaviour inside Minecraft itself (see docs/05 test report).
import { test } from "node:test";
import assert from "node:assert/strict";
import { BuildEngine, ManualGuide, compareInventory } from
    "../behavior_pack/scripts/s3d/core/build.js";
import { GhostPainter, ghostForPalette } from
    "../behavior_pack/scripts/s3d/core/holo.js";
import { ProgressBitmap, buildQueue } from
    "../behavior_pack/scripts/s3d/core/planner.js";
import { defaultSession } from "../behavior_pack/scripts/s3d/core/state.js";

const DESIGN = {
    dimensions: { x: 2, y: 2, z: 1 },
    palette: [
        { id: "minecraft:stone", states: {} },
        { id: "minecraft:oak_stairs", states: { facing_direction: 2 } },
        { id: "minecraft:unobtainium", states: {} },
    ],
    blocks: [
        { x: 0, y: 0, z: 0, paletteIndex: 0 },
        { x: 1, y: 0, z: 0, paletteIndex: 0 },
        { x: 0, y: 1, z: 0, paletteIndex: 1 },
        { x: 1, y: 1, z: 0, paletteIndex: 2 },
    ],
    layers: [],
    rooms: [],
};

class FakeDimension {
    constructor() { this.blocks = new Map(); }
    key(x, y, z) { return `${x}|${y}|${z}`; }
    getBlock(loc) {
        const id = this.blocks.get(this.key(loc.x, loc.y, loc.z));
        return id ? { typeId: id } : { typeId: "minecraft:air" };
    }
}

function makeHost(designOpts = {}) {
    const dim = new FakeDimension();
    const host = {
        dim,
        world: { getAllPlayers: () => [] },
        system: { runInterval: () => 1, clearRun: () => {} },
        getBlock: () => ({ typeId: "minecraft:air" }),
        setBlock: () => true,
        resolvePermutation(id, states) {
            if (id === "minecraft:unobtainium") throw new Error("unknown block");
            if (states && Object.keys(states).length && designOpts.rejectStates)
                throw new Error("bad state name");
            return { id, states };
        },
        setBlockPermutation(dimension, x, y, z, perm) {
            dim.blocks.set(dim.key(x, y, z), perm.id);
            return true;
        },
        spawnParticle: () => {},
        countInventory: null,
        consumeFromInventory: () => 0,
        notify: () => {},
        actionBar: () => {},
        isCreative: () => true,
    };
    return host;
}

test("auto build places every block and finishes", () => {
    const host = makeHost();
    const engine = new BuildEngine(host, { dimension: host.dim });
    const queue = buildQueue(DESIGN, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const progress = new ProgressBitmap(queue.length);
    const session = defaultSession("d");
    session.speed = 2;
    let batches = 0;
    const report = engine.runSync({
        design: DESIGN, queue, progress, session,
        onBatch: () => batches++,
    });
    assert.equal(report.placed, 3); // 4th palette id fails
    assert.equal(report.failed, 1);
    assert.equal(host.dim.blocks.size, 3);
    assert.equal(host.dim.blocks.get(host.dim.key(0, 0, 0)), "minecraft:stone");
    assert.equal(progress.nextPending(0), 3); // failed cell stays pending
    assert.ok(batches >= 1);
    assert.equal(session.finished, true);
});

test("states that fail in-game fall back to bare id and are counted", () => {
    const host = makeHost({ rejectStates: true });
    const engine = new BuildEngine(host, { dimension: host.dim });
    const queue = buildQueue(DESIGN, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const progress = new ProgressBitmap(queue.length);
    const report = engine.runSync({
        design: DESIGN, queue, progress, session: defaultSession("d"),
    });
    assert.equal(report.fallbackNoStates, 1); // stairs placed without states
    assert.equal(report.placed, 3);
});

test("inventory gate blocks placement when insufficient", () => {
    const host = makeHost();
    const engine = new BuildEngine(host, { dimension: host.dim });
    const queue = buildQueue(DESIGN, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const progress = new ProgressBitmap(queue.length);
    let totalAllowed = 2;
    const report = engine.runSync({
        design: DESIGN, queue, progress, session: defaultSession("d"),
        gate: () => totalAllowed-- > 0,
    });
    assert.equal(report.insufficientInventory, 2);
    assert.equal(report.placed, 2);
});

test("pause stops the generator; resume continues where it left", () => {
    const host = makeHost();
    const engine = new BuildEngine(host, { dimension: host.dim });
    const queue = buildQueue(DESIGN, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const progress = new ProgressBitmap(queue.length);
    const session = defaultSession("d");
    session.speed = 1; // batch per block → we can pause mid-run
    const gen = engine.autoBuild({ design: DESIGN, queue, progress, session });
    let steps = 0;
    for (const _ of gen) {
        steps++;
        if (steps === 2) engine.pause();   // generator parks on yield-loop
        if (steps === 5) engine.resume();  // resumes in place, no re-placement
        if (progress.count() === 3 && steps > 5) break;
    }
    for (const _ of gen) { /* drain to done */ }
    assert.equal(progress.count(), 3); // failed unobtainium never completes
});

test("ghost painter only replaces air and tracks drawn cells", () => {
    const host = makeHost();
    // pre-occupy one cell with real block
    host.getBlock = (dim, x, y, z) =>
        (x === 0 && y === 0 && z === 0)
            ? { typeId: "minecraft:dirt" } : { typeId: "minecraft:air" };
    const set = new Map();
    host.setBlock = (dim, x, y, z, id) => { set.set(`${x}|${y}|${z}`, id); return true; };
    const painter = new GhostPainter(host, host.dim);
    painter.drainSync(painter.paint(DESIGN, { rot: 0, offset: { x: 0, y: 0, z: 0 } }));
    assert.equal(set.size, 3); // (0,0,0) occupied → skipped
    assert.equal(set.get("0|1|0"), "s3d:ghost_wood"); // stairs → wood family
    assert.equal(set.get("1|0|0"), "s3d:ghost_stone");
    assert.equal(painter.drawn.size, 3);
    painter.drainSync(painter.clear());
    assert.equal(painter.drawn.size, 0);
    assert.equal(set.get("0|1|0"), "minecraft:air");
});

test("ghostForPalette maps families", () => {
    assert.equal(ghostForPalette(DESIGN.palette, 0), "s3d:ghost_stone");
    assert.equal(ghostForPalette([{ id: "minecraft:oak_planks" }], 0), "s3d:ghost_wood");
    assert.equal(ghostForPalette([{ id: "minecraft:glass" }], 0), "s3d:ghost_glass");
});

test("manual guide advances only on matching block at target cells", () => {
    const host = makeHost();
    const guide = new ManualGuide(host, { dimension: host.dim });
    const queue = buildQueue(DESIGN, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const progress = new ProgressBitmap(queue.length);
    const session = defaultSession("d");
    const ctx = { design: DESIGN, queue, progress, session };

    let r = guide.handlePlacement(ctx, { x: 5, y: 5, z: 5, typeId: "minecraft:stone" });
    assert.equal(r.result, "none");

    r = guide.handlePlacement(ctx, { x: 0, y: 0, z: 0, typeId: "minecraft:dirt" });
    assert.equal(r.result, "mismatch");
    assert.equal(r.want, "minecraft:stone");

    r = guide.handlePlacement(ctx, { x: 0, y: 0, z: 0, typeId: "minecraft:stone" });
    assert.equal(r.result, "advance");
    assert.equal(session.built, 1);

    const next = guide.nextTarget(ctx);
    assert.equal(next.cell.x, 1); // queue order continues
});

test("compareInventory computes exact deficits", () => {
    const tally = [{ id: "minecraft:stone", count: 3 }, { id: "minecraft:glass", count: 2 }];
    const have = new Map([["minecraft:stone", 5], ["minecraft:glass", 1]]);
    const cmp = compareInventory(have, tally);
    assert.equal(cmp.rows[0].missing, 0);
    assert.equal(cmp.rows[1].missing, 1);
    assert.equal(cmp.canBuildFully, false);
    assert.equal(compareInventory(new Map([["minecraft:stone", 3], ["minecraft:glass", 2]]), tally).canBuildFully, true);
});
