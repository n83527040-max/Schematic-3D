// Session state with world dynamic-property persistence (store-agnostic).
// `store` implements getDynamicProperty/setDynamicProperty. Pure logic —
// node-testable with a Map-backed store.

import { rotateXZ } from "./planner.js";

export const STATE_VERSION = 1;

export function defaultSession(designId) {
  return {
    v: STATE_VERSION,
    designId,
    rot: 0,
    offset: { x: 0, y: 0, z: 0 },
    anchorSaved: null,          // last player-provided anchor for quick return
    hiddenLayers: [],          // layer ids
    roomOnly: null,            // room id or null
    mode: "preview",           // preview | manual | auto
    holo: "ghosts",            // ghosts | particles | off
    speed: 16,                 // blocks per tick for auto build
    assist: "validate",        // validate | easy
    consumeMaterials: false,   // survival deduction toggle (default off)
    progress: "",              // hex bitmap for current queue
    built: 0,
    failed: 0,
    running: false,
    finished: false,
  };
}

export function sessionKey(playerId) {
  return `s3d:session:${playerId}`;
}
export const CONFIG_KEY = "s3d:config";

export function saveSession(store, playerId, session) {
  try {
    store.setDynamicProperty(sessionKey(playerId), JSON.stringify(session));
    return true;
  } catch {
    return false; // property size limits etc. — caller reports
  }
}

export function loadSession(store, playerId) {
  const raw = store.getDynamicProperty(sessionKey(playerId));
  if (typeof raw !== "string" || !raw) return null;
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!data || data.v !== STATE_VERSION) {
    // future: migration hooks land here; unknown versions are dropped.
    return null;
  }
  return { ...defaultSession(data.designId), ...data };
}

export function clearSession(store, playerId) {
  store.setDynamicProperty(sessionKey(playerId), undefined);
}

export function loadConfig(store) {
  const raw = store.getDynamicProperty(CONFIG_KEY);
  if (typeof raw === "string") {
    try { return { giveItem: true, batchLog: false, ...JSON.parse(raw) }; }
    catch { /* fallthrough */ }
  }
  return { giveItem: true, batchLog: false };
}

export function saveConfig(store, cfg) {
  try { store.setDynamicProperty(CONFIG_KEY, JSON.stringify(cfg)); } catch { /* ignore */ }
}

/** Offset helpers: move the anchor; clamped to integer block coords. */
export function moveSession(session, dx, dy, dz) {
  session.offset = {
    x: Math.trunc(session.offset.x + dx),
    y: Math.trunc(session.offset.y + dy),
    z: Math.trunc(session.offset.z + dz),
  };
  session.progress = ""; // queue identity changed → rebuild from scratch
  session.finished = false;
  return session;
}

export function rotateSession(session) {
  session.rot = (session.rot + 1) % 4;
  // anchor stays the min-corner; rotated footprint keeps origin at corner
  session.progress = "";
  session.finished = false;
  return session;
}
