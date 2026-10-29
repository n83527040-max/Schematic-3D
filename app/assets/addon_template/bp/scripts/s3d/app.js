// Schematic 3D Builder — runtime controller.
// Owns sessions, painters, build engines and event reactions. Forms call
// into this; the game-API surface is limited to platform.js/host.
import { DESIGNS } from "./data/index.js";
import {
    defaultSession, loadSession, saveSession, clearSession,
    loadConfig, saveConfig, moveSession, rotateSession,
} from "./core/state.js";
import {
    buildQueue, worldBounds, findConflicts, ProgressBitmap, tallyMaterials,
} from "./core/planner.js";
import { GhostPainter, ghostForPalette } from "./core/holo.js";
import { BuildEngine, ManualGuide, compareInventory } from "./core/build.js";
import { host } from "./platform.js";
import { tr } from "./ui/lang.js";

const DESIGN_MAP = new Map(DESIGNS.map((d) => [d.id, d]));

export class S3DApp {
    constructor() {
        this.sessions = new Map();   // playerId -> session
        this.painters = new Map();   // playerId -> GhostPainter
        this.engines = new Map();    // playerId -> {engine, jobId}
        this.guide = new Map();      // playerId -> ManualGuide
        this.contexts = new Map();   // playerId -> ctx {design, queue, progress}
        this.lastHighlight = new Map();
        this.config = { giveItem: true, lang: "en" };
    }

    // ------------------------------------------------------------ lifecycle
    init() {
        this.config = loadConfig(host.world);
        host.system.runInterval(() => this.tick(), 5);
    }

    sessionFor(player, designId) {
        let s = this.sessions.get(player.id);
        if (!s && designId) {
            s = defaultSession(designId);
            this.sessions.set(player.id, s);
        }
        if (!s) s = loadSession(host.world, player.id);
        if (s) this.sessions.set(player.id, s);
        return s ?? null;
    }

    persist(player) {
        const s = this.sessions.get(player.id);
        if (s) saveSession(host.world, player.id, s);
    }

    designOf(player) {
        const s = this.sessions.get(player.id);
        return s ? DESIGN_MAP.get(s.designId) : undefined;
    }

    // ------------------------------------------------------------- contexts
    rebuildContext(player) {
        const s = this.sessions.get(player.id);
        const design = this.designOf(player);
        if (!s || !design) return null;
        const view = {
            rot: s.rot,
            offset: s.offset,
            hiddenLayers: s.hiddenLayers,
            roomOnly: s.roomOnly,
        };
        const queue = buildQueue(design, view);
        const progress = ProgressBitmap.fromHex(queue.length, s.progress);
        const ctx = {
            design, queue, progress, session: s,
            forgetGhost: (cell) => this.painterFor(player).drawn
                .delete(`${cell.x}|${cell.y}|${cell.z}`),
            onBatch: (b, t) => {
                s.built = b; s.progress = progress.toHex();
                this.persist(player);
                host.actionBar(player, `${this.t("progress", b, t)}`);
            },
            onDone: (report) => {
                s.running = false;
                s.progress = progress.toHex();
                this.persist(player);
                host.notify(player, this.t("built", report.placed, report.failed));
                if (report.insufficientInventory > 0)
                    host.notify(player, `⚠ insufficient inventory: ${report.insufficientInventory}`);
                host.notify(player, this.t("done"));
            },
            gate: s.consumeMaterials && !host.isCreative(player)
                ? (pe) => {
                    const have = host.countInventory(player, new Set([pe.id]))?.get(pe.id) ?? 0;
                    if (have <= 0) return false;
                    host.consumeFromInventory(player, pe.id, 1);
                    return true;
                }
                : null,
        };
        this.contexts.set(player.id, ctx);
        return ctx;
    }

    t(key, ...args) {
        return tr(this.config.lang, key, ...args);
    }

    painterFor(player) {
        let p = this.painters.get(player.id);
        if (!p) {
            p = new GhostPainter(host, host.dimensionFor(player));
            this.painters.set(player.id, p);
        }
        return p;
    }

    // ------------------------------------------------------------- painting
    async repaint(player, { clearFirst = true } = {}) {
        const painter = this.painterFor(player);
        if (clearFirst) painter.drainSync(painter.clear());
        const ctx = this.rebuildContext(player);
        if (!ctx) return;
        const s = this.sessions.get(player.id);
        if (s.holo === "off") return;
        if (s.holo === "particles") return; // handled by ticker elsewhere
        painter.drainSync(painter.paint(ctx.design, {
            rot: s.rot, offset: s.offset, hiddenLayers: s.hiddenLayers,
            roomOnly: s.roomOnly,
        }));
    }

    hidePreview(player) {
        const painter = this.painterFor(player);
        painter.drainSync(painter.clear());
    }

    // ------------------------------------------------------------- anchors
    setAnchorFromLook(player) {
        const block = host.targetedBlock(player, 64);
        if (!block) return false;
        const s = this.sessionFor(player);
        if (!s) return false;
        s.offset = { x: block.x, y: block.y + 1, z: block.z };
        s.progress = ""; s.finished = false;
        this.persist(player);
        return true;
    }

    snapToGround(player) {
        const s = this.sessionFor(player);
        const design = this.designOf(player);
        if (!s || !design) return false;
        const dim = host.dimensionFor(player);
        const b = worldBounds(design, { rot: s.rot, offset: s.offset });
        const cxs = [b.min.x, b.max.x, (b.min.x + b.max.x) >> 1];
        const czs = [b.min.z, b.max.z, (b.min.z + b.max.z) >> 1];
        let top = dim.getBlock(s.offset).y;
        let found = null;
        for (const cx of cxs) for (const cz of czs) {
            const tb = dim.getTopmostBlock({ x: cx, z: cz });
            if (tb && (found === null || tb.y > found)) found = tb.y;
        }
        if (found !== null) s.offset.y = found + 1;
        s.progress = ""; s.finished = false;
        this.persist(player);
        return true;
    }

    move(player, dx, dy, dz) {
        const s = this.sessionFor(player);
        if (!s) return false;
        moveSession(s, dx, dy, dz);
        this.persist(player);
        return true;
    }

    rotate(player) {
        const s = this.sessionFor(player);
        if (!s) return false;
        rotateSession(s);
        this.persist(player);
        return true;
    }

    // ----------------------------------------------------------- auto build
    conflictCount(player) {
        const ctx = this.rebuildContext(player) ?? this.contexts.get(player.id);
        if (!ctx) return { total: 0, conflicts: [] };
        const conflicts = findConflicts(
            ctx.queue,
            (x, y, z) => {
                const b = host.getBlock(host.dimensionFor(player), x, y, z);
                return b ? { id: b.typeId } : null;
            },
            (pIdx) => ghostForPalette(ctx.design.palette, pIdx),
        );
        return { total: ctx.queue.length, conflicts };
    }

    startAuto(player) {
        const ctx = this.rebuildContext(player);
        const s = this.sessions.get(player.id);
        if (!ctx || !s) return false;
        if (ctx.queue.length === 0) return false;
        const engine = new BuildEngine(host, {
            dimension: host.dimensionFor(player),
        });
        this.engines.set(player.id, { engine });
        s.running = true; s.mode = "auto";
        this.persist(player);
        const job = host.runJob(engine.autoBuild(ctx));
        this.engines.set(player.id, { engine, job });
        return true;
    }

    pauseAuto(player) {
        const e = this.engines.get(player.id);
        e?.engine.pause();
        const s = this.sessions.get(player.id);
        if (s) { s.running = false; this.persist(player); }
    }

    resumeAuto(player) {
        const e = this.engines.get(player.id);
        if (e) { e.engine.resume(); return true; }
        // engine lost (world reload) → restart from saved progress
        return this.startAuto(player);
    }

    stopAuto(player) {
        const e = this.engines.get(player.id);
        if (e) {
            e.engine.stop();
            if (e.job != null) host.clearRun(e.job);
            this.engines.delete(player.id);
        }
        const s = this.sessions.get(player.id);
        if (s) { s.running = false; this.persist(player); }
    }

    // -------------------------------------------------------- manual mode
    startManual(player) {
        const s = this.sessionFor(player);
        if (!s) return false;
        s.mode = "manual";
        this.persist(player);
        if (!this.guide.has(player.id))
            this.guide.set(player.id, new ManualGuide(host, {
                dimension: host.dimensionFor(player),
            }));
        return true;
    }

    handlePlace(player, placed) {
        const s = this.sessions.get(player.id);
        if (!s || s.mode !== "manual") return { handled: false };
        const ctx = this.rebuildContext(player);
        if (!ctx) return { handled: false };
        const result = this.guide.get(player.id).handlePlacement(ctx, placed);
        if (result.result === "advance") {
            s.progress = ctx.progress.toHex();
            this.persist(player);
        }
        return { handled: true, ...result };
    }

    // ------------------------------------------------------------ materials
    materialsView(player, withInventory) {
        const ctx = this.rebuildContext(player);
        if (!ctx) return null;
        const tally = tallyMaterials(ctx.queue, ctx.design.palette);
        let cmp = null;
        if (withInventory) {
            const avail = host.countInventory(
                player, new Set(tally.map((r) => r.id)));
            cmp = avail === null ? "unavailable" : compareInventory(avail, tally);
        }
        return { tally, cmp };
    }

    // --------------------------------------------------------------- ticker
    tick() {
        for (const [playerId] of this.sessions) {
            const player = this.findPlayer(playerId);
            if (!player) continue;
            const s = this.sessions.get(playerId);
            if (s?.mode !== "manual" || s.running) continue;
            const ctx = this.contexts.get(playerId);
            if (!ctx) continue;
            const next = ctx.progress.nextPending(0);
            if (next < 0) continue;
            const cell = ctx.queue[next];
            const pe = ctx.design.palette[cell.p];
            const label = `${this.t("nextBlock")}: ${pe?.id ?? "?"} @ ${cell.x} ${cell.y} ${cell.z}`;
            host.actionBar(player, label);
            const key = `${cell.x}|${cell.y}|${cell.z}`;
            if (this.lastHighlight.get(playerId) !== key) {
                const prev = this.lastHighlight.get(playerId);
                if (prev) {
                    const [px, py, pz] = prev.split("|").map(Number);
                    host.setBlock(host.dimensionFor(player), px, py, pz, "minecraft:air");
                }
                host.setBlock(host.dimensionFor(player), cell.x, cell.y, cell.z, "s3d:highlight");
                this.lastHighlight.set(playerId, key);
            }
        }
    }

    findPlayer(id) {
        try {
            for (const p of host.world.getAllPlayers()) if (p.id === id) return p;
        } catch { /* ignore */ }
        return undefined;
    }
}
