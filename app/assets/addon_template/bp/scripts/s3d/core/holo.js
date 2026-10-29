// Hologram painters. Host interface (dependency-injected for tests):
//   host.getBlock(dimension, x, y, z) -> { typeId } | undefined
//   host.setBlock(dimension, x, y, z, blockIdOrPermutation) -> true/false
//   host.spawnParticle(name, {x,y,z}) -> void
//   host.system.runJob(gen) -> job id
import { ghostBlockId } from "./tint.js";
import { buildQueue, worldBounds } from "./planner.js";

const MAX_GHOSTS_PER_TICK = 256;

export function ghostForPalette(palette, index) {
  const id = palette[index]?.id ?? "minecraft:air";
  return ghostBlockId(id) ?? "s3d:ghost_white";
}

export class GhostPainter {
  constructor(host, dimension = "overworld") {
    this.host = host;
    this.dimension = dimension;
    this.drawn = new Set();          // "x|y|z" currently holding ghost blocks
    this.jobId = null;
  }

  planCells(design, view) {
    return buildQueue(design, { ...view, hiddenLayers: view.hiddenLayers?.length ? view.hiddenLayers : null });
  }

  /** Place ghosts only where the world is air; existing blocks stay intact.
   *  Returns a generator that a runJob can consume; also usable synchronously
   *  in tests via drainSync(). */
  *paint(design, view, onProgress) {
    const cells = this.planCells(design, view);
    const pal = design.palette;
    let sinceYield = 0;
    for (const c of cells) {
      const key = `${c.x}|${c.y}|${c.z}`;
      const occ = this.host.getBlock(this.dimension, c.x, c.y, c.z);
      if (occ && occ.typeId !== "minecraft:air") continue;
      if (this.setGhost(c, ghostForPalette(pal, c.p))) {
        this.drawn.add(key);
        if (onProgress) onProgress(this.drawn.size, cells.length);
      }
      if (++sinceYield >= MAX_GHOSTS_PER_TICK) {
        sinceYield = 0;
        yield;
      }
    }
  }

  drainSync(gen) {
    for (const _ of gen) { /* run in one go (tests / small designs) */ }
  }

  setGhost(cell, ghostId) {
    return this.host.setBlock(this.dimension, cell.x, cell.y, cell.z, ghostId);
  }

  /** Restore every drawn ghost cell back to air (never touches real blocks:
   *  only cells we know we set). */
  *clear() {
    let n = 0;
    for (const key of this.drawn) {
      const [x, y, z] = key.split("|").map(Number);
      this.host.setBlock(this.dimension, x, y, z, "minecraft:air");
      this.drawn.delete(key);
      if (++n % MAX_GHOSTS_PER_TICK === 0) yield;
    }
  }

  highlight(cell) {
    if (!cell) return false;
    return this.host.setBlock(this.dimension, cell.x, cell.y, cell.z, "s3d:highlight");
  }

  region() {
    const keys = [...this.drawn];
    return keys.map((k) => k.split("|").map(Number));
  }
}

export class ParticlePainter {
  /** Cheaper, world-safe mode: one small particle per block, refreshed on a
   *  slow cycle around the anchor (billboards are axis-independent). */
  constructor(host, dimension = "overworld") {
    this.host = host;
    this.dimension = dimension;
    this.interval = null;
  }

  start(getDesign, getView) {
    this.stop();
    this.interval = this.host.system.runInterval(() => {
      const design = getDesign();
      const view = getView();
      if (!design || !view) return;
      const cells = buildQueue(design, view);
      const b = worldBounds(design, view);
      const budget = Math.min(cells.length, 120);
      this._cursor = ((this._cursor ?? 0) + budget) % Math.max(1, cells.length);
      for (let i = 0; i < budget; i++) {
        const c = cells[(this._cursor + i) % cells.length];
        this.host.spawnParticle("minecraft:villager_happy", { x: c.x + 0.5, y: c.y + 0.5, z: c.z + 0.5 });
      }
    }, 10);
  }

  stop() {
    if (this.interval != null) {
      this.host.system.clearRun(this.interval);
      this.interval = null;
    }
  }
}
