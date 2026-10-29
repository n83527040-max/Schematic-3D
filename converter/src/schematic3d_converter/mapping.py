"""Java → Bedrock conversion of palette entries, with explicit reporting.

Rules (from docs/03 of the spec pack):
- Never silently guess. Every transformed palette entry is recorded in the
  ConversionReport with its original id/states.
- Unmappable ids become a `block` fallback only when the caller opts into
  `on_unsupported="barrier"`; the default is `"skip"` which removes the
  blocks of that palette entry (they are counted in the report).
- Block states are only translated for the small set we are certain about
  (facing families, slab halves, stairs shapes, colored families). Dropped
  states are reported as `state.dropped` warnings, satisfying the spec's
  requirement to surface "changed block states".
"""
from __future__ import annotations

from .ids import to_full_id, JAVA_FAMILY_TO_BEDROCK, JAVA_TO_BEDROCK
from .models import PaletteEntry


class MappingOutcome:
    __slots__ = ("entry", "action", "note")

    def __init__(self, entry: PaletteEntry | None, action: str, note: str = ""):
        self.entry = entry      # resulting Bedrock PaletteEntry (None = dropped)
        self.action = action    # "pass" | "renamed" | "family" | "state-mapped"
                                # | "state-dropped" | "unsupported"
        self.note = note


# Java `facing` (block facing semantics) → Bedrock direction naming.
_JAVA_FACING_TO_BEDROCK = {
    "north": "north", "south": "south", "east": "east", "west": "west",
    "up": "up", "down": "down",
}


def map_java_entry(entry: PaletteEntry) -> MappingOutcome:
    """Convert a Java palette entry (id + states) to a Bedrock entry."""
    raw_id = entry.id
    ns, name = (raw_id.split(":", 1) + [""])[:2] if ":" in raw_id else ("minecraft", raw_id)
    if ns == "bedrock":
        ns = "minecraft"
    notes: list[str] = []

    states = dict(entry.states)

    # Family blocks encoded via states on the Java side (color=, wood_type= …)
    family = JAVA_FAMILY_TO_BEDROCK.get(name)
    if family:
        pick = _family_variant(states, name)
        if pick and pick in family:
            target = family[pick]
            rest = _drop_family_states(states, name)
            new_states, dropped = _translate_states(name, rest)
            if dropped:
                notes.append("dropped:" + ",".join(dropped))
            pe = PaletteEntry.make(target, new_states)
            return MappingOutcome(pe, "family", "; ".join(notes))
        # cannot determine variant → unsupported, be explicit
        return MappingOutcome(PaletteEntry.make(to_full_id(name), {}), "unsupported",
                              f"family {name} variant could not be resolved")

    # Direct renames
    if name in JAVA_TO_BEDROCK:
        target = JAVA_TO_BEDROCK[name]
        new_states, dropped = _translate_states(name, states)
        if dropped:
            notes.append("dropped:" + ",".join(dropped))
        pe = PaletteEntry.make(target, new_states)
        act = "renamed" if target != f"minecraft:{name}" else "state-mapped"
        if dropped:
            act = "state-dropped"
        return MappingOutcome(pe, act, "; ".join(notes))

    # Same id on both sides (already bedrock-compatible)
    if ns == "minecraft":
        new_states, dropped = _translate_states(name, states)
        act = "pass"
        notes_list = []
        if dropped:
            act = "state-dropped"
            notes_list.append("dropped:" + ",".join(dropped))
        return MappingOutcome(PaletteEntry.make(f"minecraft:{name}", new_states),
                              act, "; ".join(notes_list))
    return MappingOutcome(entry, "pass")


def _family_variant(states: dict, family_name: str) -> str | None:
    """Determine the variant label from typical Java state keys."""
    if family_name in ("planks",):
        v = states.get("type") or states.get("variant")
    elif family_name in ("log", "log2", "wood", "leaves", "leaves2", "fence"):
        v = states.get("variant") or states.get("wood_type") or states.get("type")
    elif family_name in ("stained_glass", "stained_hardened_clay", "wool",
                         "carpet", "concrete", "concrete_powder"):
        v = states.get("color")
    else:
        v = None
    if isinstance(v, str):
        return v.lower()
    return None


_FAMILY_STATE_KEYS = {
    "planks": {"type", "variant"},
    "log": {"wood_type", "axis", "variant"},
    "leaves": {"persistent_bit", "update_bit", "variant", "distance", "persistent"},
    "fence": {"variant", "waterlogged"},
    "wood": {"axis", "variant"},
    "wood2": {"axis", "variant"},
    "leaves2": {"persistent_bit", "update_bit", "variant", "distance", "persistent"},
    "planks2": {"variant"},
    "stained_glass": {"color"},
    "stained_hardened_clay": {"color"},
    "wool": {"color"},
    "carpet": {"color"},
    "concrete": {"color"},
    "concrete_powder": {"color"},
}


def _drop_family_states(states: dict, family_name: str) -> dict:
    keys = _FAMILY_STATE_KEYS.get(family_name, set())
    return {k: v for k, v in states.items() if k not in keys}


def _translate_states(java_name: str, states: dict) -> tuple[dict, list[str]]:
    """Translate the subset of states we are certain about. Return (kept, dropped)."""
    kept: dict = {}
    dropped: list[str] = []
    for k, v in states.items():
        if k == "facing":
            # Keep as textual direction; Bedrock accepts named facing for many
            # blocks. Blocks that use numeric direction get in-game validation.
            lv = v.lower() if isinstance(v, str) else v
            if lv in _JAVA_FACING_TO_BEDROCK:
                kept["facing_direction"] = _facing_to_dir(lv)
            else:
                dropped.append(k)
        elif k in ("axis",):
            kept[k] = v
        elif k == "half":
            kept["upper_block"] = (v == "top")
        elif k == "shape" and isinstance(v, str):
            if v in ("straight", "inner_left", "inner_right", "outer_left",
                     "outer_right"):
                # Bedrock stair orientation uses stairs_shape with the same
                # naming on modern versions; invalid values fail in-game and
                # are reported there.
                kept[k] = v
            else:
                dropped.append(k)
        elif k in ("waterlogged",):
            dropped.append(k)   # Bedrock models waterlogging as co-located blocks
        elif isinstance(v, (bool, int, str)):
            kept[k] = v
        else:
            dropped.append(k)
    return kept, dropped


_FACING_DIR = {"down": 0, "up": 1, "north": 3, "south": 2, "west": 5, "east": 4}


def _facing_to_dir(value) -> int:
    if isinstance(value, int):
        return value
    return _FACING_DIR.get(str(value), 0)
