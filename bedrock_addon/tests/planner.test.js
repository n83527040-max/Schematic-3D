import { test } from "node:test";
import assert from "node:assert/strict";
import {
    rotateXZ, rotateBounds, buildQueue, worldBounds, findConflicts,
    ProgressBitmap, tallyMaterials, chunkQueue,
} from "../behavior_pack/scripts/s3d/core/planner.js";

const design = {
    dimensions: { x: 3, y: 2, z: 1 },
    palette: [
        { id: "minecraft:stone" },
        { id: "minecraft:glass" },
        { id: "minecraft:oak_planks" },
    ],
    blocks: [
        { x: 0, y: 0, z: 0, paletteIndex: 0 },
        { x: 1, y: 0, z: 0, paletteIndex: 0 },
        { x: 2, y: 0, z: 0, paletteIndex: 0 },
        { x: 0, y: 1, z: 0, paletteIndex: 1 },
        { x: 1, y: 1, z: 0, paletteIndex: 2 },
        { x: 2, y: 1, z: 0, paletteIndex: 1 },
    ],
    layers: [
        { id: "floor1", yMin: 0, yMax: 0 },
        { id: "floor2", yMin: 1, yMax: 1 },
    ],
    rooms: [],
};

test("rotation: four 90° steps are identity", () => {
    let x = 1, z = 0;
    const dims = { x: 3, y: 2, z: 5 };
    for (let i = 0; i < 4; i++) {
        const r = rotateXZ(x, z, dims, i + 1);
        // re-derive dims through the cycle
        if (i + 1 === 4) {
            assert.deepEqual([r.x, r.z], [1, 0]);
        }
    }
    // single-step round trip: rot1 then rotate space swapped twice = identity on 4
    const s1 = rotateXZ(1, 0, { x: 3, y: 2, z: 5 }, 1);
    const s2 = rotateXZ(s1.x, s1.z, { x: 5, y: 2, z: 3 }, 1);
    const s3 = rotateXZ(s2.x, s2.z, { x: 3, y: 2, z: 5 }, 1);
    const s4 = rotateXZ(s3.x, s3.z, { x: 5, y: 2, z: 3 }, 1);
    assert.deepEqual([s4.x, s4.z], [1, 0]);
});

test("rotation maps footprint correctly for 90°", () => {
    const dims = { x: 3, y: 2, z: 1 };
    const r = rotateXZ(2, 0, dims, 1);
    assert.equal(r.w, 1);
    assert.equal(r.d, 3);
    assert.ok(r.x >= 0 && r.x < 1);
    assert.ok(r.z >= 0 && r.z < 3);
});

test("queue is sorted bottom-up and translated by offset", () => {
    const q = buildQueue(design, { rot: 0, offset: { x: 100, y: 64, z: -30 } });
    assert.equal(q.length, 6);
    assert.deepEqual(q[0], { x: 100, y: 64, z: -30, p: 0 });
    for (let i = 1; i < q.length; i++) assert.ok(q[i].y >= q[i - 1].y);
});

test("hidden layers filter the queue", () => {
    const q = buildQueue(design, { rot: 0, offset: { x: 0, y: 0, z: 0 }, hiddenLayers: ["floor1"] });
    assert.equal(q.length, 3);
    assert.ok(q.every((c) => c.y === 1));
});

test("room filter clips x/z bounds", () => {
    const withRoom = {
        ...design,
        rooms: [{ id: "left", bounds: { x0: 0, z0: 0, x1: 0, z1: 0 } }],
    };
    const q = buildQueue(withRoom, { rot: 0, offset: { x: 0, y: 0, z: 0 }, roomOnly: "left" });
    assert.equal(q.length, 2); // (0,0,0) and (0,1,0)
});

test("rotateBounds rotates room bbox with design", () => {
    const dims = { x: 3, y: 2, z: 1 };
    const b = rotateBounds({ x0: 0, z0: 0, x1: 2, z1: 0 }, dims, 1);
    assert.equal(b.x1 - b.x0 + 1, 1); // footprint swapped: width 1
    assert.equal(b.z1 - b.z0 + 1, 3);
});

test("worldBounds swaps size on 90° rotation", () => {
    const b0 = worldBounds(design, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const b1 = worldBounds(design, { rot: 1, offset: { x: 0, y: 0, z: 0 } });
    assert.deepEqual(b0.size, { x: 3, y: 2, z: 1 });
    assert.deepEqual(b1.size, { x: 1, y: 2, z: 3 });
});

test("conflict detection ignores air and our own ghost layer", () => {
    const q = buildQueue(design, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const occupied = new Map([
        ["1|0|0", "minecraft:air"],
        ["0|0|0", "s3d:ghost_stone"],
        ["2|1|0", "minecraft:dirt"],
    ]);
    const conflicts = findConflicts(
        q,
        (x, y, z) => {
            const id = occupied.get(`${x}|${y}|${z}`);
            return id ? { id } : { id: "minecraft:air" };
        },
        () => "s3d:ghost_stone",
    );
    assert.equal(conflicts.length, 1);
    assert.deepEqual(conflicts[0].cell, { x: 2, y: 1, z: 0, p: 1 });
});

test("progress bitmap round-trips through hex", () => {
    const p = new ProgressBitmap(100);
    p.set(0); p.set(7); p.set(8); p.set(99);
    const hex = p.toHex();
    const p2 = ProgressBitmap.fromHex(100, hex);
    assert.ok(p2.get(0) && p2.get(7) && p2.get(8) && p2.get(99));
    assert.ok(!p2.get(1) && !p2.get(50));
    assert.equal(p2.count(), 4);
    assert.equal(p2.nextPending(0), 1);
});

test("nextPending scans forward from index", () => {
    const p = new ProgressBitmap(5);
    p.set(0); p.set(1);
    assert.equal(p.nextPending(0), 2);
    p.set(2); p.set(3); p.set(4);
    assert.equal(p.nextPending(0), -1);
});

test("materials tally merges ids and totals the queue", () => {
    const q = buildQueue(design, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const rows = tallyMaterials(q, design.palette);
    const map = Object.fromEntries(rows.map((r) => [r.id, r.count]));
    assert.deepEqual(map, {
        "minecraft:stone": 3, "minecraft:glass": 2, "minecraft:oak_planks": 1,
    });
});

test("chunkQueue splits by size with remainder", () => {
    const q = buildQueue(design, { rot: 0, offset: { x: 0, y: 0, z: 0 } });
    const batches = chunkQueue(q, 4);
    assert.equal(batches.length, 2);
    assert.equal(batches[1].length, 2);
});
