"""Semantic validation for schematic3d-build documents.

The JSON Schema (schemas/) catches shape errors. This module adds the
semantic layer that a schema cannot express: coordinate bounds vs declared
dimensions, palette index references, duplicate coordinates, layer/room
consistency, and volume caps. Errors are collected (not raised one-by-one)
so the UI can show a complete report; the importer decides whether to accept
warnings.
"""
from __future__ import annotations

from .models import (
    Design, DesignError, Layer, PaletteEntry, Room, check_dimension,
    normalize_state_value, validate_identifier, validate_state_key,
    MAX_BLOCKS, MAX_LIST_FIELDS, MAX_PALETTE, FORMAT_ID, SCHEMA_VERSION,
)

MAX_ERRORS_IN_REPORT = 200


class Issue:
    __slots__ = ("level", "code", "message", "path")

    def __init__(self, level: str, code: str, message: str, path: str | None = None):
        self.level = level  # "error" | "warning"
        self.code = code
        self.message = message
        self.path = path

    def to_dict(self) -> dict:
        out = {"level": self.level, "code": self.code, "message": self.message}
        if self.path:
            out["path"] = self.path
        return out

    def __repr__(self) -> str:  # pragma: no cover
        return f"Issue({self.level},{self.code},{self.path},{self.message})"


class ValidationReport:
    def __init__(self) -> None:
        self.issues: list[Issue] = []
        self.truncated = False

    def error(self, code: str, message: str, path: str | None = None):
        self._add("error", code, message, path)

    def warning(self, code: str, message: str, path: str | None = None):
        self._add("warning", code, message, path)

    def _add(self, level: str, code: str, message: str, path: str | None):
        if len(self.issues) >= MAX_ERRORS_IN_REPORT:
            self.truncated = True
            return
        self.issues.append(Issue(level, code, message, path))

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "error"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "warning"]

    @property
    def ok(self) -> bool:
        return not self.errors

    def to_dict(self) -> dict:
        return {
            "valid": self.ok,
            "errorCount": len(self.errors),
            "warningCount": len(self.warnings),
            "truncated": self.truncated,
            "issues": [i.to_dict() for i in self.issues],
        }


def parse_and_validate(doc: dict, *, id_check=None) -> tuple[Design, ValidationReport]:
    """Validate a raw JSON document into a Design.

    Never raises for user data errors: everything lands in the report.
    Raises DesignError only for programmer errors (should not happen).
    Returns (design_or_partial, report). When report.ok is False the design
    is None-safe: caller must check ok before use.
    """
    rep = ValidationReport()

    if not isinstance(doc, dict):
        rep.error("root.type", "root must be a JSON object")
        return None, rep  # type: ignore[return-value]

    if doc.get("format") != FORMAT_ID:
        rep.error("format", f"format must be {FORMAT_ID!r}", "$.format")
    sv = doc.get("schemaVersion")
    if sv != SCHEMA_VERSION:
        rep.error("schemaVersion",
                  f"schemaVersion {sv!r} not supported (expected {SCHEMA_VERSION})",
                  "$.schemaVersion")

    name = doc.get("name")
    if not isinstance(name, str) or not (1 <= len(name) <= 200):
        rep.error("name.type", "name must be a string of 1..200 chars", "$.name")
        name = str(name)[:200] if name is not None else "Untitled"

    desc = doc.get("description")
    if desc is not None and (not isinstance(desc, str) or len(desc) > 4000):
        rep.warning("description.type", "description ignored (must be string ≤4000)",
                    "$.description")
        desc = None

    dims = doc.get("dimensions")
    dx = dy = dz = 0
    if not isinstance(dims, dict):
        rep.error("dimensions.type", "dimensions must be an object", "$.dimensions")
    else:
        try:
            dx = check_dimension(dims.get("x"), axis="x")
            dy = check_dimension(dims.get("y"), axis="y")
            dz = check_dimension(dims.get("z"), axis="z")
        except DesignError as exc:
            rep.error("dimensions.range", exc.message, "$.dimensions")

    palette_raw = doc.get("palette")
    palette: list[PaletteEntry] = []
    if not isinstance(palette_raw, list) or not palette_raw:
        rep.error("palette.type", "palette must be a non-empty array", "$.palette")
    else:
        if len(palette_raw) > MAX_PALETTE:
            rep.error("palette.size",
                      f"palette has {len(palette_raw)} entries (max {MAX_PALETTE})",
                      "$.palette")
        seen_perm: dict[PaletteEntry, int] = {}
        for i, entry in enumerate(palette_raw):
            path = f"$.palette[{i}]"
            if not isinstance(entry, dict):
                rep.error("palette.entry", f"palette entry {i} must be an object", path)
                continue
            bid = entry.get("id")
            try:
                bid = validate_identifier(bid, where=path + ".id")
            except DesignError as exc:
                rep.error("palette.id", exc.message, exc.path or path)
                continue
            states_raw = entry.get("states", {})
            states: dict = {}
            if states_raw is None:
                states_raw = {}
            if not isinstance(states_raw, dict):
                rep.error("palette.states", f"states of {bid!r} must be an object",
                          path + ".states")
            else:
                for k, v in states_raw.items():
                    try:
                        validate_state_key(k, where=path + ".states")
                        states[k] = normalize_state_value(k, v, where=path + ".states")
                    except DesignError as exc:
                        rep.error("palette.state", exc.message, exc.path or path)
            pe = PaletteEntry.make(bid, states)
            if pe in seen_perm:
                rep.warning("palette.duplicate",
                            f"palette entry {i} duplicates entry {seen_perm[pe]}; will merge",
                            path)
            else:
                seen_perm[pe] = len(palette)
                palette.append(pe)
        # remap function captured below
    # Build a definitive index map (original palette position -> merged position)
    _merge_map: dict[int, int] = {}
    if isinstance(palette_raw, list):
        seen_perm = {}
        merged_len = 0
        for i, entry in enumerate(palette_raw):
            if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
                _merge_map[i] = -1
                continue
            try:
                bid = validate_identifier(entry["id"], where="")
                st = entry.get("states") or {}
                norm = {}
                if isinstance(st, dict):
                    for k, v in st.items():
                        if isinstance(k, str):
                            try:
                                norm[k] = normalize_state_value(k, v, where="")
                            except DesignError:
                                norm[k] = v
                pe = PaletteEntry.make(bid, norm)
            except DesignError:
                _merge_map[i] = -1
                continue
            if pe in seen_perm:
                _merge_map[i] = seen_perm[pe]
            else:
                seen_perm[pe] = merged_len
                _merge_map[i] = merged_len
                merged_len += 1

    blocks_raw = doc.get("blocks")
    blocks = []
    coords_seen: dict[tuple[int, int, int], int] = {}
    if not isinstance(blocks_raw, list) or not blocks_raw:
        rep.error("blocks.type", "blocks must be a non-empty array", "$.blocks")
    else:
        if len(blocks_raw) > MAX_BLOCKS:
            rep.error("blocks.size",
                      f"blocks array has {len(blocks_raw)} entries (max {MAX_BLOCKS})",
                      "$.blocks")
            blocks_raw = blocks_raw[:MAX_BLOCKS]
        for i, b in enumerate(blocks_raw):
            path = f"$.blocks[{i}]"
            if not isinstance(b, dict):
                rep.error("blocks.entry", f"block entry {i} must be an object", path)
                continue
            try:
                x, y, z = b["x"], b["y"], b["z"]
                pi = b["paletteIndex"]
            except KeyError as exc:
                rep.error("blocks.fields", f"missing key {exc.args[0]!r}", path)
                continue
            ok = True
            for axis, val in (("x", x), ("y", y), ("z", z)):
                if not isinstance(val, int) or isinstance(val, bool):
                    rep.error("blocks.coord", f"{axis} must be an integer, got {val!r}",
                              path)
                    ok = False
                elif dx and not (0 <= val < ({"x": dx, "y": dy, "z": dz}[axis])):
                    rep.error("blocks.bounds",
                              f"{axis}={val} outside declared dimensions "
                              f"({ {'x': dx, 'y': dy, 'z': dz}[axis]} )", path)
                    ok = False
            if not isinstance(pi, int) or isinstance(pi, bool):
                rep.error("blocks.paletteIndex",
                          f"paletteIndex must be an integer, got {pi!r}", path)
                ok = False
            else:
                if not (0 <= pi < len(palette_raw or [])):
                    rep.error("blocks.paletteIndex",
                              f"paletteIndex {pi} out of palette range", path)
                    ok = False
                else:
                    mapped = _merge_map.get(pi, -1)
                    if mapped is None or mapped < 0 or mapped >= len(palette):
                        rep.error("blocks.paletteIndex",
                                  f"paletteIndex {pi} references an invalid entry", path)
                        ok = False
                    else:
                        pi = mapped
            if not ok:
                continue
            key = (x, y, z)
            if key in coords_seen:
                rep.error("blocks.duplicate",
                          f"coordinate {key} already defined at $.blocks[{coords_seen[key]}]",
                          path)
                continue
            coords_seen[key] = i
            from .models import BlockEntry
            blocks.append(BlockEntry(x, y, z, pi))

    if dx and dy and dz and blocks:
        vol = dx * dy * dz
        if vol > 16 * 1024 * 1024:
            rep.error("volume", f"bounding volume {vol} exceeds 16M cells")

    layers: list[Layer] = []
    layers_raw = doc.get("layers", [])
    if layers_raw and not isinstance(layers_raw, list):
        rep.error("layers.type", "layers must be an array", "$.layers")
        layers_raw = []
    if len(layers_raw or []) > MAX_LIST_FIELDS:
        rep.error("layers.size", "too many layers", "$.layers")
        layers_raw = layers_raw[:MAX_LIST_FIELDS]
    layer_ids = set()
    for i, l in enumerate(layers_raw or []):
        path = f"$.layers[{i}]"
        if not isinstance(l, dict):
            rep.error("layers.entry", "layer must be an object", path)
            continue
        lid = l.get("id")
        if not isinstance(lid, str) or not lid or len(lid) > 80:
            rep.error("layers.id", "layer id must be a string (1..80)", path)
            continue
        if lid in layer_ids:
            rep.error("layers.duplicate", f"duplicate layer id {lid!r}", path)
            continue
        y0, y1 = l.get("yMin"), l.get("yMax")
        if not (isinstance(y0, int) and not isinstance(y0, bool)
                and isinstance(y1, int) and not isinstance(y1, bool)):
            rep.error("layers.range", "yMin/yMax must be integers", path)
            continue
        if y0 < 0 or y1 < 0 or y0 > y1 or (dy and y1 >= dy):
            rep.error("layers.range", f"layer {lid!r} range [{y0},{y1}] invalid "
                      f"for design height {dy}", path)
            continue
        layer_ids.add(lid)
        lname = l.get("name")
        layers.append(Layer(lid, lname if isinstance(lname, str) else None, y0, y1))

    rooms: list[Room] = []
    rooms_raw = doc.get("rooms", [])
    if rooms_raw and not isinstance(rooms_raw, list):
        rep.error("rooms.type", "rooms must be an array", "$.rooms")
        rooms_raw = []
    if len(rooms_raw or []) > MAX_LIST_FIELDS:
        rep.error("rooms.size", "too many rooms", "$.rooms")
        rooms_raw = rooms_raw[:MAX_LIST_FIELDS]
    room_ids = set()
    for i, r in enumerate(rooms_raw or []):
        path = f"$.rooms[{i}]"
        if not isinstance(r, dict):
            rep.error("rooms.entry", "room must be an object", path)
            continue
        rid = r.get("id")
        if not isinstance(rid, str) or not rid or len(rid) > 80:
            rep.error("rooms.id", "room id must be a string (1..80)", path)
            continue
        if rid in room_ids:
            rep.error("rooms.duplicate", f"duplicate room id {rid!r}", path)
            continue
        bounds = r.get("bounds")
        if not isinstance(bounds, dict):
            rep.error("rooms.bounds", "bounds object required", path)
            continue
        vals = []
        bad = False
        for k in ("x0", "z0", "x1", "z1"):
            v = bounds.get(k)
            if not isinstance(v, int) or isinstance(v, bool):
                rep.error("rooms.bounds", f"bounds.{k} must be integer", path)
                bad = True
                break
            vals.append(v)
        if bad:
            continue
        x0, z0, x1, z1 = vals
        if x0 > x1 or z0 > z1:
            rep.error("rooms.bounds", f"room {rid!r} bounds inverted", path)
            continue
        if dx and (x0 < 0 or z0 < 0 or x1 >= dx or z1 >= dz):
            rep.error("rooms.bounds", f"room {rid!r} bounds outside footprint", path)
            continue
        lid = r.get("layerId")
        if lid is not None and lid not in layer_ids:
            rep.warning("rooms.layer", f"room {rid!r} references unknown layer {lid!r}",
                        path)
            lid = None
        rname = r.get("name")
        rooms.append(Room(rid, rname if isinstance(rname, str) else None,
                          lid if isinstance(lid, str) else None,
                          (x0, z0, x1, z1)))

    meta = doc.get("metadata", {})
    if not isinstance(meta, dict):
        rep.warning("metadata.type", "metadata must be an object; ignored",
                    "$.metadata")
        meta = {}

    # Coverage warnings -------------------------------------------------
    if dx and dy and dz and blocks:
        filled = len(blocks)
        vol = dx * dy * dz
        if filled == vol:
            pass
        elif filled > vol:
            rep.error("volume.overflow",
                      f"{filled} blocks cannot fit in volume {vol} (dedup already applied)")
    te = doc.get("targetEdition")
    if te not in (None, "bedrock"):
        rep.warning("targetEdition",
                    f"targetEdition={te!r}; this app targets Bedrock, conversion may "
                    f"need a Java→Bedrock mapping pass", "$.targetEdition")

    if id_check is not None:
        for i, p in enumerate(palette):
            verdict = id_check(p.id)
            if verdict == "unknown":
                rep.warning("palette.id.unknown",
                            f"block id {p.id!r} is not in the known Bedrock block list; "
                            f"it will be attempted in-game and reported on failure",
                            f"$.palette[{i}].id")
            elif verdict == "invalid":
                rep.error("palette.id.invalid",
                          f"block id {p.id!r} is malformed", f"$.palette[{i}].id")

    design = Design(
        name=name, description=desc, dimensions=(dx or 1, dy or 1, dz or 1),
        palette=palette, blocks=blocks, layers=layers, rooms=rooms,
        metadata=meta,
    )
    return design, rep
