import { test } from "node:test";
import assert from "node:assert/strict";
import {
    defaultSession, loadSession, saveSession, clearSession, sessionKey,
    loadConfig, saveConfig, moveSession, rotateSession, STATE_VERSION,
} from "../behavior_pack/scripts/s3d/core/state.js";

class FakeWorld {
    constructor() { this.store = new Map(); }
    getDynamicProperty(k) { return this.store.get(k); }
    setDynamicProperty(k, v) {
        if (v === undefined) this.store.delete(k);
        else this.store.set(k, v);
    }
}

test("session save → load restores all fields", () => {
    const w = new FakeWorld();
    const s = defaultSession("cottage12x8x12");
    s.rot = 2; s.offset = { x: 10, y: 64, z: -3 }; s.progress = "ff00";
    s.built = 42; s.mode = "manual";
    assert.ok(saveSession(w, "p1", s));
    const back = loadSession(w, "p1");
    assert.equal(back.designId, "cottage12x8x12");
    assert.equal(back.rot, 2);
    assert.deepEqual(back.offset, { x: 10, y: 64, z: -3 });
    assert.equal(back.built, 42);
    assert.equal(back.mode, "manual");
});

test("unknown version sessions are dropped (not half-read)", () => {
    const w = new FakeWorld();
    w.setDynamicProperty(sessionKey("p1"), JSON.stringify({ v: 99, designId: "x" }));
    assert.equal(loadSession(w, "p1"), null);
    w.setDynamicProperty(sessionKey("p1"), "{not json");
    assert.equal(loadSession(w, "p1"), null);
});

test("clearSession removes the entry", () => {
    const w = new FakeWorld();
    saveSession(w, "p1", defaultSession("d"));
    clearSession(w, "p1");
    assert.equal(loadSession(w, "p1"), null);
    assert.equal(w.store.size, 0);
});

test("missing fields backfill from defaults", () => {
    const w = new FakeWorld();
    w.setDynamicProperty(sessionKey("p9"), JSON.stringify({
        v: STATE_VERSION, designId: "tower", rot: 1,
    }));
    const s = loadSession(w, "p9");
    assert.deepEqual(s.offset, { x: 0, y: 0, z: 0 });
    assert.equal(s.speed, 16);
    assert.equal(s.mode, "preview");
});

test("config defaults + persistence", () => {
    const w = new FakeWorld();
    assert.deepEqual(loadConfig(w), { giveItem: true, batchLog: false });
    w.setDynamicProperty("s3d:config", JSON.stringify({ giveItem: false }));
    const cfg = loadConfig(w);
    assert.equal(cfg.giveItem, false);
    saveConfig(w, { giveItem: true, lang: "ar" });
    assert.equal(loadConfig(w).lang, "ar");
});

test("move and rotate reset progress (queue identity changed)", () => {
    const s = defaultSession("d");
    s.progress = "ffff";
    moveSession(s, 1, 0, 0);
    assert.equal(s.progress, "");
    assert.deepEqual(s.offset, { x: 1, y: 0, z: 0 });
    s.progress = "ff";
    rotateSession(s);
    assert.equal(s.rot, 1);
    assert.equal(s.progress, "");
});
