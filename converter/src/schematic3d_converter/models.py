"""Domain models for the `schematic3d-build` internal format (v1).

These dataclasses are the single source of truth shared by all parsers,
exporters and reporting. The on-disk JSON shape is documented in
`schemas/schematic3d-build.v1.schema.json`.
"""
from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from typing import Any

FORMAT_ID = "schematic3d-build"
SCHEMA_VERSION = 1

_BLOCK_ID_RE = re.compile(r"^[a-z0-9_.-]+:[a-z0-9_./-]+$")
_SNAKE_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# Hard safety limits (see docs/02_formats). Values beyond these must be
# rejected before any heavy work happens.
MAX_DIMENSION = 512          # blocks along X/Y/Z per design
MAX_BLOCKS = 2_000_000       # total explicit block entries
MAX_PALETTE = 4096           # unique permutations
MAX_LIST_FIELDS = 4096       # layers + rooms


class DesignError(Exception):
    """Base error with structured location info for reporting."""

    def __init__(self, message: str, *, path: str | None = None):
        super().__init__(message)
        self.message = message
        self.path = path

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"{self.path}: {self.message}" if self.path else self.message


@dataclass(frozen=True)
class PaletteEntry:
    """A block id plus its state map (already validated)."""

    id: str
    states: tuple[tuple[str, Any], ...] = ()

    @staticmethod
    def make(id_: str, states: dict | None = None) -> "PaletteEntry":
        items = tuple(sorted((states or {}).items()))
        return PaletteEntry(id_, items)

    @property
    def states_dict(self) -> dict:
        return dict(self.states)

    def to_json(self) -> dict:
        out: dict[str, Any] = {"id": self.id}
        if self.states:
            out["states"] = self.states_dict
        return out

    def command_token(self) -> str:
        """Bedrock `/setblock <x> <y> <z> <id>[state=value,...]` token."""
        if not self.states:
            return self.id
        parts = []
        for k, v in self.states:
            if isinstance(v, bool):
                sval = "true" if v else "false"
            else:
                sval = str(v)
            parts.append(f"{k}={sval}")
        return f"{self.id}[{','.join(parts)}]"


@dataclass(frozen=True)
class BlockEntry:
    x: int
    y: int
    z: int
    palette_index: int

    def key(self) -> tuple[int, int, int]:
        return (self.x, self.y, self.z)


@dataclass
class Layer:
    id: str
    name: str | None
    y_min: int
    y_max: int

    def to_json(self) -> dict:
        out: dict[str, Any] = {"id": self.id, "yMin": self.y_min, "yMax": self.y_max}
        if self.name:
            out["name"] = self.name
        return out


@dataclass
class Room:
    id: str
    name: str | None
    layer_id: str | None
    bounds: tuple[int, int, int, int]  # x0, z0, x1, z1 inclusive
    to_json_out: dict = field(default_factory=dict)

    def to_json(self) -> dict:
        out: dict[str, Any] = {
            "id": self.id,
            "bounds": {"x0": self.bounds[0], "z0": self.bounds[1],
                       "x1": self.bounds[2], "z1": self.bounds[3]},
        }
        if self.name:
            out["name"] = self.name
        if self.layer_id:
            out["layerId"] = self.layer_id
        return out


@dataclass
class Design:
    """A complete, validated schematic3d-build design."""

    name: str
    description: str | None
    dimensions: tuple[int, int, int]           # x, y, z
    palette: list[PaletteEntry]
    blocks: list[BlockEntry]
    layers: list[Layer] = field(default_factory=list)
    rooms: list[Room] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)

    # ---------- derived ----------
    @property
    def size(self) -> tuple[int, int, int]:
        return self.dimensions

    @property
    def block_count(self) -> int:
        return len(self.blocks)

    def block_at(self, x: int, y: int, z: int) -> BlockEntry | None:
        for b in reversed(self.blocks):
            if (b.x, b.y, b.z) == (x, y, z):
                return b
        return None

    def iter_blocks(self):
        yield from self.blocks

    def palette_index_for(self, entry: PaletteEntry) -> int | None:
        for i, p in enumerate(self.palette):
            if p == entry:
                return i
        return None

    # ---------- serialization ----------
    def to_json_dict(self) -> dict:
        dx, dy, dz = self.dimensions
        out: dict[str, Any] = {
            "format": FORMAT_ID,
            "schemaVersion": SCHEMA_VERSION,
            "name": self.name,
            "targetEdition": "bedrock",
            "dimensions": {"x": dx, "y": dy, "z": dz},
            "palette": [p.to_json() for p in self.palette],
            "blocks": [
                {"x": b.x, "y": b.y, "z": b.z, "paletteIndex": b.palette_index}
                for b in self.blocks
            ],
        }
        if self.description:
            out["description"] = self.description
        if self.layers:
            out["layers"] = [l.to_json() for l in self.layers]
        if self.rooms:
            out["rooms"] = [r.to_json() for r in self.rooms]
        if self.metadata:
            out["metadata"] = self.metadata
        return out

    def to_json(self, pretty: bool = False) -> str:
        d = self.to_json_dict()
        if pretty:
            return json.dumps(d, ensure_ascii=False, indent=2)
        return json.dumps(d, ensure_ascii=False, separators=(",", ":"))


def validate_identifier(id_: str, *, where: str) -> str:
    if not isinstance(id_, str) or not _BLOCK_ID_RE.match(id_):
        raise DesignError(
            f"block id must be namespaced like 'minecraft:stone', got {id_!r}",
            path=where,
        )
    return id_


def validate_state_key(key: str, *, where: str) -> str:
    if not isinstance(key, str) or not _SNAKE_RE.match(key):
        raise DesignError(f"invalid block state name {key!r}", path=where)
    return key


def normalize_state_value(key: str, value: Any, *, where: str) -> Any:
    """Accept JSON values and coerce to canonical python values.

    Booleans stay bool, ints stay int (reject float with fraction),
    strings stay strings. Anything else is rejected.
    """
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if math.isfinite(value) and value.is_integer():
            return int(value)
        raise DesignError(f"state {key!r}: float value {value!r} not allowed",
                          path=where)
    if isinstance(value, str):
        if len(value) > 64:
            raise DesignError(f"state {key!r}: string value too long", path=where)
        return value
    raise DesignError(f"state {key!r}: unsupported value type {type(value).__name__}",
                      path=where)


def check_dimension(dim: int, *, axis: str) -> int:
    if not isinstance(dim, int) or isinstance(dim, bool):
        raise DesignError(f"dimensions.{axis} must be an integer")
    if dim < 1 or dim > MAX_DIMENSION:
        raise DesignError(
            f"dimensions.{axis}={dim} out of range 1..{MAX_DIMENSION}")
    return dim
