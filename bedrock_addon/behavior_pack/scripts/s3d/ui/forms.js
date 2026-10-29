// All in-game UI forms. Every action routes through app.js; forms only
// present state and capture choices. Every destructive/starting action is
// behind an explicit confirm (spec requirement).
import { ActionFormData, ModalFormData, MessageFormData } from "@minecraft/server-ui";
import { DESIGNS } from "../data/index.js";
import { tr, LANGS } from "./lang.js";
import { saveConfig } from "../core/state.js";
import { host } from "../platform.js";

const L = (app) => (key, ...args) => tr(app.config.lang, key, ...args);

export function openRoot(player, app) {
    const t = L(app);
    const form = new ActionFormData().title(t("title"));
    if (DESIGNS.length === 0) {
        form.body(t("noDesigns"));
        form.button(t("langSetting"));
        form.show(player).then((res) => {
            if (res.selection === 0) openLang(player, app);
        });
        return;
    }
    form.body(`${t("designs")} (${DESIGNS.length})`);
    for (const d of DESIGNS) {
        form.button(`§b▣ ${d.name}§r\n§7${d.dimensions.join("×")} · ${d.blockCount} ${t("blockCount")}§r`);
    }
    form.button(`⚙ ${t("langSetting")}`);
    form.show(player).then((res) => {
        if (res.canceled) return;
        if (res.selection === DESIGNS.length) { openLang(player, app); return; }
        const design = DESIGNS[res.selection];
        app.sessionFor(player, design.id);
        openDetails(player, app, design);
    }).catch((e) => host.notify(player, String(e)));
}

function openDetails(player, app, design) {
    const t = L(app);
    const s = app.sessionFor(player, design.id);
    const form = new ActionFormData()
        .title(design.name)
        .body(`${t("dims")}: ${design.dimensions.join("×")}\n`
             + `${t("blockCount")}: ${design.blockCount}\n`
             + `Anchored at §e${s.offset.x} ${s.offset.y} ${s.offset.z}§r rot §e${s.rot * 90}°§r`);
    const actions = [];
    actions.push([t("anchor"), () => {
        if (app.setAnchorFromLook(player)) host.notify(player, t("anchorSet"));
        else host.notify(player, t("noTarget"));
        openDetails(player, app, design);
    }]);
    actions.push([`${t("move")} → X+/Z-`, () => { app.move(player, 1, 0, 0); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([`${t("move")} → X-/Z+`, () => { app.move(player, -1, 0, 0); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([`${t("move")} → +1`, () => { app.move(player, 0, 0, 1); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([`${t("move")} → -1`, () => { app.move(player, 0, 0, -1); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([`${t("moveY")} ↑`, () => { app.move(player, 0, 1, 0); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([`${t("moveY")} ↓`, () => { app.move(player, 0, -1, 0); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([t("snapGround"), () => { app.snapToGround(player); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([t("rotate"), () => { app.rotate(player); app.repaint(player); openDetails(player, app, design); }]);
    actions.push([t("layers"), () => openLayers(player, app, design)]);
    actions.push([t("materials"), () => openMaterials(player, app, false)]);
    actions.push([t("compareInv"), () => openMaterials(player, app, true)]);
    actions.push([`§a${t("preview")}§r`, () => { app.repaint(player); }]);
    actions.push([`§7${t("hideGhosts")}§r`, () => { app.hidePreview(player); }]);
    actions.push([`§e${t("manual")}§r`, () => { app.startManual(player); host.notify(player, t("nextBlock") + ": ✓"); }]);
    actions.push([`§b${t("auto")}§r`, () => confirmAuto(player, app, design)]);
    actions.push([t("pause"), () => { app.pauseAuto(player); host.notify(player, t("pausedMsg")); }]);
    actions.push([t("resume"), () => { app.resumeAuto(player); }]);
    actions.push([t("stop"), () => { app.stopAuto(player); app.hidePreview(player); }]);
    actions.push([t("speed"), () => openSpeed(player, app)]);
    actions.push([t("consume") + (s.consumeMaterials ? " ✓" : " ✗"),
        () => { const ss = app.sessions.get(player.id); ss.consumeMaterials = !ss.consumeMaterials; app.persist(player); openDetails(player, app, design); }]);
    actions.push(["⬅ menu", () => openRoot(player, app)]);

    for (const [label] of actions) form.button(label);
    form.show(player).then((res) => {
        if (res.canceled) return;
        actions[res.selection]?.[1]();
    }).catch((e) => host.notify(player, String(e)));
}

function confirmAuto(player, app, design) {
    const t = L(app);
    const { total, conflicts } = app.conflictCount(player);
    const proceed = () => {
        new MessageFormData()
            .title(t("auto"))
            .body(t("startConfirm", total))
            .button1(t("yes")).button2(t("no"))
            .show(player).then((res) => {
                if (res.selection === 0) app.startAuto(player);
            }).catch(() => {});
    };
    if (conflicts.length > 0) {
        new MessageFormData()
            .title("⚠")
            .body(t("conflicts", conflicts.length))
            .button1(t("yes")).button2(t("no"))
            .show(player).then((res) => { if (res.selection === 0) proceed(); })
            .catch(() => {});
    } else {
        proceed();
    }
}

function openLayers(player, app, design) {
    const t = L(app);
    const s = app.sessions.get(player.id);
    const form = new ModalFormData().title(t("layers"));
    const layers = design.layers ?? [];
    const toggles = layers.map((l) =>
        [`${l.name ?? l.id} (y ${l.yMin}–${l.yMax})`, !s.hiddenLayers.includes(l.id)]);
    for (const [label, on] of toggles) form.toggle(label, { defaultValue: on });
    const rooms = (design.rooms ?? []).map((r) => r.name ?? r.id);
    const dropdownLabel = rooms.length ? `${t("roomFilter")}` : `${t("roomFilter")} (—)`;
    if (rooms.length) {
        form.dropdown(dropdownLabel, [t("allRooms"), ...rooms],
            { defaultValueIndex: rooms.indexOf(s.roomOnly) + 1 > 0 ? rooms.indexOf(s.roomOnly) + 1 : 0 });
    }
    form.show(player).then((res) => {
        if (res.canceled) return;
        const values = res.formValues ?? [];
        const hidden = [];
        toggles.forEach(([label], i) => { if (values[i] === false) hidden.push(layers[i].id); });
        s.hiddenLayers = hidden;
        if (rooms.length) {
            const idx = values[toggles.length] ?? 0;
            s.roomOnly = idx > 0 ? design.rooms[idx - 1].id : null;
        }
        app.persist(player);
        app.repaint(player);
    }).catch(() => {});
}

function openMaterials(player, app, withInv) {
    const t = L(app);
    const view = app.materialsView(player, withInv);
    if (!view) { host.notify(player, t("noSession")); return; }
    let body = view.tally.map((r) => `§f${r.id}§7 × ${r.count}`).join("\n")
        || "—";
    if (view.cmp === "unavailable") body += `\n\n§c${t("inventoryUnavailable")}`;
    else if (view.cmp) {
        body += "\n" + view.cmp.rows.map((r) => {
            const col = r.missing === 0 ? "§a" : "§c";
            return `${col}${r.id}§7 ${r.have}/${r.need}`;
        }).join("\n");
        body += view.cmp.canBuildFully ? "\n§a✔" : "\n§c✘";
    }
    new ActionFormData().title(t("materials")).body(body)
        .button(t("compareInv")).button("⬅")
        .show(player).then((res) => {
            if (res.selection === 0) openMaterials(player, app, true);
            else if (res.selection === 1) openDetails(player, app, app.designOf(player));
        }).catch(() => {});
}

function openSpeed(player, app) {
    const t = L(app);
    const s = app.sessions.get(player.id);
    if (!s) return;
    new ModalFormData().title(t("speed"))
        .slider(t("speed"), 4, 128, { valueStep: 2, defaultValue: s.speed })
        .show(player).then((res) => {
            if (res.canceled) return;
            s.speed = Math.round(res.formValues?.[0] ?? s.speed);
            app.persist(player);
        }).catch(() => {});
}

function openLang(player, app) {
    const form = new ActionFormData().title(L(app)("langSetting"));
    for (const lang of LANGS) form.button(lang.toUpperCase());
    form.show(player).then((res) => {
        if (res.canceled) return;
        app.config.lang = LANGS[res.selection];
        saveConfig(host.world, app.config);
    }).catch(() => {});
}
