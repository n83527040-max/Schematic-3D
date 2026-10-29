// Entry point for the Schematic 3D Builder behavior pack.
// Wires game events into the app controller. Target: @minecraft/server
// 2.10.0-beta / @minecraft/server-ui 2.2.0-beta (verified against the
// 1.26.40-stable type packages — see docs/00_environment_and_feasibility).
import { world, system } from "@minecraft/server";
import { S3DApp } from "./s3d/app.js";
import { host } from "./s3d/platform.js";
import { openRoot } from "./s3d/ui/forms.js";

const app = new S3DApp();
const MENU_ITEM = "s3d:menu";

function safe(fn, label) {
    return (...args) => {
        try { fn(...args); }
        catch (e) { console.warn(`[s3d] ${label}: ${e?.stack ?? e}`); }
    };
}

system.run(() => {
    app.init();
    world.afterEvents.playerSpawn.subscribe(safe((ev) => {
        const p = ev.player;
        if (!ev.initialSpawn) return;
        if (app.config.giveItem) {
            // only top up when the player does not already carry one
            try {
                if (host.hasItem(p, MENU_ITEM) === 0)
                    host.giveItem(p, MENU_ITEM, 1);
            } catch { /* inventory unavailable */ }
        }
        // restore session + preview lazily on first menu open; nothing heavy here
    }, "playerSpawn"));
});

// Menu item opens the UI (main hand, on block or in air).
world.beforeEvents.itemUse.subscribe(safe((ev) => {
    const player = ev.source;
    if (player?.typeId !== "minecraft:player") return;
    let held;
    try {
        const inv = player.getComponent("minecraft:inventory")?.container;
        held = inv?.getItem(player.selectedSlotIndex ?? 0);
    } catch { /* ignore */ }
    if (held?.typeId !== MENU_ITEM) return;
    ev.cancel = true;
    system.run(() => openRoot(player, app));
}, "itemUse"));

// Chat bridge: "!s3d ..." (chatSend does not see slash commands).
world.beforeEvents.chatSend.subscribe(safe((ev) => {
    const msg = ev.message.trim();
    if (!msg.toLowerCase().startsWith("!s3d")) return;
    ev.cancel = true;
    const parts = msg.split(/\s+/).slice(1);
    const player = ev.sender;
    system.run(() => {
        const cmd = (parts[0] ?? "menu").toLowerCase();
        switch (cmd) {
            case "menu": case "open": openRoot(player, app); break;
            case "anchor": host.notify(player,
                app.setAnchorFromLook(player) ? "✓" : "✗"); break;
            case "preview": app.repaint(player); break;
            case "hide": app.hidePreview(player); break;
            case "stop": app.stopAuto(player); app.hidePreview(player); break;
            case "pause": app.pauseAuto(player); break;
            case "resume": app.resumeAuto(player); break;
            case "manual": app.startManual(player); break;
            case "auto": {
                const { total, conflicts } = app.conflictCount(player);
                if (conflicts.length === 0) app.startAuto(player);
                else host.notify(player,
                    `⚠ ${conflicts.length} conflicting blocks — use the menu to confirm.`);
                break;
            }
            case "speed": {
                const n = parseInt(parts[1] ?? "16", 10);
                const s = app.sessions.get(player.id);
                if (s && Number.isFinite(n)) {
                    s.speed = Math.max(4, Math.min(128, n));
                    app.persist(player);
                    host.notify(player, `speed=${s.speed}`);
                }
                break;
            }
            case "materials": {
                const v = app.materialsView(player, false);
                host.notify(player, v ? v.tally.map((r) => `${r.id} ×${r.count}`).slice(0, 8).join("\n") : "—");
                break;
            }
            default: host.notify(player, "!s3d menu|anchor|preview|hide|manual|auto|pause|resume|stop|speed N|materials");
        }
    });
}, "chatSend"));

// Manual guided build: validate placements.
world.afterEvents.playerPlaceBlock.subscribe(safe((ev) => {
    const player = ev.player;
    const block = ev.block;
    if (!block) return;
    const res = app.handlePlace(player, {
        x: block.x, y: block.y, z: block.z, typeId: block.typeId,
    });
    if (res.handled && res.result === "mismatch") {
        host.notify(player, `⚠ ${res.want} — placed ${res.got}`);
    }
}, "playerPlaceBlock"));

// Breaking a ghost cell should drop it from our drawn-set bookkeeping.
world.afterEvents.playerBreakBlock.subscribe(safe((ev) => {
    const painter = app.painters.get(ev.player?.id);
    if (painter && ev.block) painter.drawn.delete(`${ev.block.x}|${ev.block.y}|${ev.block.z}`);
}, "playerBreakBlock"));
