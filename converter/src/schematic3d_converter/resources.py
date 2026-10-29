"""Material (resource) accounting computed strictly from block data.

Spec rule: never take counts from textual descriptions — every quantity comes
from the actual `blocks` list. Aggregations: total, per layer (floor), per
room. Air and structure voids are excluded.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field

from .models import Design

_NON_MATERIAL_IDS = {
    "minecraft:air", "minecraft:structure_void", "minecraft:void_air",
}


@dataclass
class MaterialRow:
    id: str                       # block id (states normalized into label)
    label: str                    # human label incl. notable states
    count: int = 0
    state_breakdown: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        out = {"id": self.id, "label": self.label, "count": self.count}
        if self.state_breakdown:
            out["stateBreakdown"] = dict(self.state_breakdown)
        return out


@dataclass
class MaterialSummary:
    total_blocks: int
    material_blocks: int
    rows: list[MaterialRow]
    per_layer: dict[str, list[MaterialRow]]
    per_room: dict[str, list[MaterialRow]]

    def to_dict(self) -> dict:
        return {
            "totalBlocks": self.total_blocks,
            "materialBlocks": self.material_blocks,
            "rows": [r.to_dict() for r in self.rows],
            "perLayer": {k: [r.to_dict() for r in v]
                         for k, v in self.per_layer.items()},
            "perRoom": {k: [r.to_dict() for r in v]
                        for k, v in self.per_room.items()},
        }


def _label(palette_entry) -> str:
    if not palette_entry.states:
        return palette_entry.id
    bits = ",".join(f"{k}={v}" for k, v in palette_entry.states)
    return f"{palette_entry.id}[{bits}]"


def material_summary(design: Design, *, merge_same_id: bool = True) -> MaterialSummary:
    """Count blocks per palette permutation (optionally merged per id).

    merge_same_id=True aggregates `stone_bricks[mossy=false]` and
    `stone_bricks[mossy=true]` into one row `minecraft:stone_bricks` with the
    summed count, and keeps state breakdowns in `states` when unique.
    """
    counter: Counter[str] = Counter()
    state_detail: dict[str, Counter] = {}
    layer_counters: dict[str, Counter[str]] = {l.id: Counter() for l in design.layers}
    room_counters: dict[str, Counter[str]] = {r.id: Counter() for r in design.rooms}
    material_blocks = 0
    for b in design.blocks:
        if b.palette_index >= len(design.palette):
            continue
        pe = design.palette[b.palette_index]
        if pe.id in _NON_MATERIAL_IDS:
            continue
        material_blocks += 1
        row_key = pe.id if merge_same_id else _label(pe)
        counter[row_key] += 1
        for k, v in pe.states:
            state_detail.setdefault(row_key, Counter())[f"{k}={v}"] += 1
        # layer bucket
        for l in design.layers:
            if l.y_min <= b.y <= l.y_max:
                if l.id in layer_counters:
                    layer_counters[l.id][row_key] += 1
        # room bucket (point-in-bounds; layer constraint when declared)
        for r in design.rooms:
            if r.bounds[0] <= b.x <= r.bounds[2] and r.bounds[1] <= b.z <= r.bounds[3]:
                in_layer = True
                if r.layer_id:
                    lay = next((x for x in design.layers if x.id == r.layer_id), None)
                    in_layer = lay is not None and lay.y_min <= b.y <= lay.y_max
                if in_layer:
                    room_counters[r.id][row_key] += 1

    def _rows(c: Counter) -> list[MaterialRow]:
        rows = []
        for key, cnt in c.most_common():
            rows.append(MaterialRow(
                id=key.split("[")[0], label=key, count=cnt,
                state_breakdown=dict(state_detail.get(key, {})),
            ))
        return rows

    return MaterialSummary(
        total_blocks=len(design.blocks),
        material_blocks=material_blocks,
        rows=_rows(counter),
        per_layer={k: _rows(v) for k, v in layer_counters.items() if v},
        per_room={k: _rows(v) for k, v in room_counters.items() if v},
    )
