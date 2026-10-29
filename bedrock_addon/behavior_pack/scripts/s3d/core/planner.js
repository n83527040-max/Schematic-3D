// Pure planning logic: transforms, queues, conflicts, progress bitmaps.
// No Minecraft imports — fully unit-testable in node (see bedrock_addon/tests).

/** Rotate a design-local (x,z) by rot*90° inside the design footprint.
 *  Returns rotated coordinates plus the rotated footprint size (swap on 90/270). */
export function rotateXZ(x, z, dims, rot) {
  const steps = ((rot % 4) + 4) % 4;
  let cx = x, cz = z;
  let W = dims.x, D = dims.z;
  for (let i = 0; i < steps; i++) {
    const nx = D - 1 - cz;
    const nz = cx;
    cx = nx; cz = nz;
    const t = W; W = D; D = t;
  }
  return { x: cx, z: cz, w: W, d: D };
}

/** Rotate a room bbox in design space for a given rot (returns new bounds). */
export function rotateBounds(b, dims, rot) {
  const pts = [[b.x0, b.z0], [b.x1, b.z0], [b.x0, b.z1], [b.x1, b.z1]]
    .map(([x, z]) => rotateXZ(x, z, dims, rot));
  const xs = pts.map((p) => p.x);
  const zs = pts.map((p) => p.z);
  return { x0: Math.min(...xs), z0: Math.min(...zs),
           x1: Math.max(...xs), z1: Math.max(...zs),
           w: pts[0].w, d: pts[0].d };
}

/**
 * Build the ordered placement queue in world coordinates.
 * view = { rot, offset {x,y,z}, hiddenLayers:Set|null, roomOnly:string|null }
 * Cells: { x, y, z, p } with p = paletteIndex; index order y→x→z (bottom-up).
 */
export function buildQueue(design, view) {
  const rot = view.rot ?? 0;
  const off = view.offset ?? { x: 0, y: 0, z: 0 };
  const dims = { x: design.dimensions.x, y: design.dimensions.y, z: design.dimensions.z };
  let roomBounds = null;
  if (view.roomOnly) {
    const room = (design.rooms ?? []).find((r) => r.id === view.roomOnly);
    if (room) roomBounds = rotateBounds(room.bounds, dims, rot);
  }
  const hidden = view.hiddenLayers ?? null;

  const cells = [];
  for (const b of design.blocks) {
    const r = rotateXZ(b.x, b.z, dims, rot);
    const wy = b.y + off.y;
    if (hidden && hidden.length) {
      const layer = (design.layers ?? []).find(
        (l) => l.yMin <= b.y && b.y <= l.yMax);
      if (layer && hidden.includes(layer.id)) continue;
    }
    if (roomBounds) {
      if (!(roomBounds.x0 <= r.x && r.x <= roomBounds.x1 &&
            roomBounds.z0 <= r.z && r.z <= roomBounds.z1)) continue;
    }
    cells.push({ x: r.x + off.x, y: wy, z: r.z + off.z, p: b.paletteIndex });
  }
  cells.sort((a, b2) => a.y - b2.y || a.x - b2.x || a.z - b2.z);
  return cells;
}

/** World footprint after rotation for bounds checks / region scan. */
export function worldBounds(design, view) {
  const dims = { x: design.dimensions.x, y: design.dimensions.y, z: design.dimensions.z };
  const r = rotateXZ(0, 0, dims, view.rot ?? 0);
  const off = view.offset ?? { x: 0, y: 0, z: 0 };
  return {
    min: { x: off.x, y: off.y, z: off.z },
    max: { x: off.x + r.w - 1, y: off.y + dims.y - 1, z: off.z + r.d - 1 },
    size: { x: r.w, y: dims.y, z: r.d },
  };
}

/**
 * Conflict scan (pure): for each queue cell ask `isOccupied(x,y,z) ->
 * null | {id, sameGhostId?}`. A conflict is a non-air world cell whose block
 * is neither air nor the exact ghost we would draw. `ghostOf(cell)` maps a
 * palette index to the ghost id used for preview (so previews never count as
 * conflicts).
 */
export function findConflicts(queue, isOccupied, ghostOf) {
  const conflicts = [];
  for (const cell of queue) {
    const occ = isOccupied(cell.x, cell.y, cell.z);
    if (!occ || occ.id === "minecraft:air") continue;
    const wantGhost = ghostOf ? ghostOf(cell.p) : null;
    if (wantGhost && occ.id === wantGhost) continue;
    conflicts.push({ cell, existing: occ.id });
  }
  return conflicts;
}

// ------------------------------------------------------------- progress ---

export class ProgressBitmap {
  constructor(len) {
    this.len = len;
    this.bytes = new Uint8Array(Math.ceil(len / 8));
  }
  static fromHex(len, hex) {
    const p = new ProgressBitmap(len);
    if (hex) {
      for (let i = 0; i < p.bytes.length && i * 2 + 1 < hex.length; i++)
        p.bytes[i] = parseInt(hex.substr(i * 2, 2), 16) || 0;
    }
    return p;
  }
  toHex() {
    let s = "";
    for (const byte of this.bytes) s += byte.toString(16).padStart(2, "0");
    return s;
  }
  set(i) {
    if (i < 0 || i >= this.len) return false;
    this.bytes[i >> 3] |= 1 << (i & 7);
    return true;
  }
  clear(i) {
    if (i < 0 || i >= this.len) return false;
    this.bytes[i >> 3] &= ~(1 << (i & 7)) & 0xff;
    return true;
  }
  get(i) {
    if (i < 0 || i >= this.len) return false;
    return (this.bytes[i >> 3] >> (i & 7)) & 1 === 1;
  }
  count() {
    let n = 0;
    for (const byte of this.bytes)
      for (let k = 0; k < 8; k++) if ((byte >> k) & 1) n++;
    return n;
  }
  nextPending(from = 0) {
    for (let i = from; i < this.len; i++) if (!this.get(i)) return i;
    return -1;
  }
}

/** Material tally from queue (already filtered), merged by block id. */
export function tallyMaterials(queue, palette) {
  const map = new Map();
  for (const cell of queue) {
    const id = palette[cell.p]?.id ?? "?";
    map.set(id, (map.get(id) ?? 0) + 1);
  }
  return [...map.entries()].sort((a, b) => b[1] - a[1])
    .map(([id, count]) => ({ id, count }));
}

/** Chunk ids into per-tick batches for budgeted building. Pure. */
export function chunkQueue(queue, batchSize) {
  const size = Math.max(1, Math.floor(batchSize));
  const out = [];
  for (let i = 0; i < queue.length; i += size) out.push(queue.slice(i, i + size));
  return out;
}
