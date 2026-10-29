// Build engines: automatic batched builder + guided manual builder.
//
// host interface (injected):
//   resolvePermutation(blockId, states) -> permutation (throws for bad id/state)
//   setBlockPermutation(dim, x, y, z, permutation) -> true/false
//   getBlock(dim, x, y, z) -> { typeId, permutation } | undefined
//   giveItem?(dim, stack, loc)         (manual mode helper, unused in v1)
//   countInventory?(player, idSet) -> Map<id, available>
//   consumeInventory?(player, id, n) -> consumedCount
//   notify?(player, text)
import { ProgressBitmap, tallyMaterials } from "./planner.js";
import { ghostForPalette } from "./holo.js";

export class BuildEngine {
  constructor(host, { dimension = "overworld" } = {}) {
    this.host = host;
    this.dimension = dimension;
    this.state = "idle"; // idle | running | paused | done
    this.report = { placed: 0, fallbackNoStates: 0, failed: 0,
                    insufficientInventory: 0, details: [] };
  }

  /**
   * Generator over the queue; drive it with system.runJob (in-game) or
   * iterate synchronously in tests via runSync().
   * ctx = { design, queue, progress (ProgressBitmap), session, onTickStat }
   */
  *autoBuild(ctx) {
    const { design, queue, progress, session } = ctx;
    this.state = "running";
    const pal = design.palette;
    const speed = Math.max(1, Math.min(128, session.speed | 0));
    let i = progress.nextPending(0);
    let sinceYield = 0;
    while (i !== -1) {
      const cell = queue[i];
      const pe = pal[cell.p];
      if (ctx.gate && !ctx.gate(pe)) {
        // inventory gate refused this block: skip and remember, continue work
        this.report.insufficientInventory++;
        i = progress.nextPending(i + 1);
        continue;
      }
      const ok = this.placeCell(cell, pe);
      if (ok) {
        progress.set(i);
        this.report.placed++;
        session.built = progress.count();
        // ghost (if any) is now covered; forget it so clear() won't wipe truth
        ctx.forgetGhost?.(cell);
      } else {
        this.report.failed++;
        this.report.details.push({
          at: [cell.x, cell.y, cell.z], id: pe?.id ?? "?", result: "failed",
        });
      }
      if (++sinceYield >= speed) {
        sinceYield = 0;
        ctx.onBatch?.(progress.count(), queue.length);
        yield;
        if (this.state !== "running") {
          while (this.state === "paused") yield;  // park until resumed/stopped
          if (this.state === "stopped") return;
        }
      }
      i = progress.nextPending(i + 1);
    }
    this.state = "done";
    session.finished = true;
    session.running = false;
    session.built = progress.count();
    ctx.onDone?.(this.report);
  }

  placeCell(cell, pe) {
    if (!pe) return false;
    // Try with states, fall back to bare id (state names differ across
    // editions/versions — in-game failure is reported, never hidden).
    try {
      const perm = this.host.resolvePermutation(pe.id, pe.states ?? {});
      if (this.host.setBlockPermutation(this.dimension, cell.x, cell.y, cell.z, perm))
        return true;
    } catch { /* fall through to bare id */ }
    try {
      const bare = this.host.resolvePermutation(pe.id, {});
      if (this.host.setBlockPermutation(this.dimension, cell.x, cell.y, cell.z, bare)) {
        this.report.fallbackNoStates++;
        return true;
      }
    } catch (err) {
      this.report.details.push({
        at: [cell.x, cell.y, cell.z], id: pe.id, result: "resolve-error",
        message: String(err?.message ?? err),
      });
    }
    return false;
  }

  pause() { if (this.state === "running") this.state = "paused"; }
  resume() { if (this.state === "paused") this.state = "running"; }
  stop() { this.state = "stopped"; }

  runSync(ctx) {
    for (const _ of this.autoBuild(ctx)) { /* tests */ }
    return this.report;
  }
}

/** Manual guided builder: validates player placements against the queue and
 *  advances progress. Mode "easy" optionally auto-places the design block
 *  when the player clicks the target cell with a wrong/empty hand. */
export class ManualGuide {
  constructor(host, { dimension = "overworld" } = {}) {
    this.host = host;
    this.dimension = dimension;
  }

  nextTarget(ctx) {
    const { queue, progress } = ctx;
    const i = progress.nextPending(0);
    return i === -1 ? null : { index: i, cell: queue[i] };
  }

  /** Called on playerPlaceBlock(after): returns "done" | "advance" | "none". */
  handlePlacement(ctx, placement) {
    const { design, queue, progress } = ctx;
    const key = `${placement.x}|${placement.y}|${placement.z}`;
    const hit = queue.findIndex((c, i) =>
      !progress.get(i) && `${c.x}|${c.y}|${c.z}` === key);
    if (hit < 0) return { result: "none" };
    const pe = design.palette[queue[hit].p];
    if (placement.typeId === pe.id) {
      progress.set(hit);
      ctx.session.built = progress.count();
      ctx.forgetGhost?.(queue[hit]);
      return { result: "advance", index: hit, want: pe.id };
    }
    return { result: "mismatch", index: hit, want: pe.id, got: placement.typeId };
  }

  /** Breaking a cell that is still pending: just a no-op marker (player may
   *  have cleared a wrong block). Already-built cells remain built (undo is
   *  explicitly out of scope per product decision). */
  handleBreak(ctx, loc) {
    return { result: "ignored" };
  }
}

export function materialsForView(design, queue) {
  return tallyMaterials(queue, design.palette);
}

/** Inventory comparison (read-only unless consume is true and host supports
 *  it). `missing` lists are exact: built from queue tally. */
export function compareInventory(available, queueTally) {
  const out = [];
  let canBuildFully = true;
  for (const row of queueTally) {
    const have = available?.get(row.id) ?? 0;
    const missing = Math.max(0, row.count - have);
    if (missing > 0) canBuildFully = false;
    out.push({ id: row.id, need: row.count, have, missing });
  }
  return { rows: out, canBuildFully };
}
