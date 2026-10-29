import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { ghostTintFor, ghostBlockId, GHOST_BLOCKS } from
    "../behavior_pack/scripts/s3d/core/tint.js";

const vectors = JSON.parse(readFileSync(
    new URL("../shared/tint_vectors.json", import.meta.url), "utf-8"));

test("golden vectors match the implementation", () => {
    for (const v of vectors) {
        assert.equal(ghostTintFor(v.id), v.tint, `vector mismatch for ${v.id}`);
    }
});

test("every tint result resolves to a registered ghost block id", () => {
    for (const v of vectors) {
        if (v.tint === null) continue;
        assert.ok(GHOST_BLOCKS.includes(ghostBlockId(v.id)),
            `no block json for ${v.id} → ${v.tint}`);
    }
});

test("air maps to null (never drawn)", () => {
    assert.equal(ghostTintFor("minecraft:air"), null);
    assert.equal(ghostTintFor("minecraft:structure_void"), null);
});
