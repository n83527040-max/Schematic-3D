"""Schema/semantic validation tests for the internal JSON format."""
from __future__ import annotations

import copy
import json

import pytest

from schematic3d_converter.validate import parse_and_validate
from schematic3d_converter.models import (PaletteEntry, BlockEntry, Design,
                                          MAX_DIMENSION)
from schematic3d_converter.parsers.schematic3d_json import (
    load_json_bytes, ParseError, schema_check)


def base_doc():
    return {
        "format": "schematic3d-build",
        "schemaVersion": 1,
        "name": "Test House",
        "targetEdition": "bedrock",
        "dimensions": {"x": 2, "y": 1, "z": 2},
        "palette": [{"id": "minecraft:stone", "states": {}}],
        "blocks": [
            {"x": 0, "y": 0, "z": 0, "paletteIndex": 0},
            {"x": 1, "y": 0, "z": 0, "paletteIndex": 0},
            {"x": 0, "y": 0, "z": 1, "paletteIndex": 0},
        ],
    }


def test_minimal_valid():
    design, rep = parse_and_validate(base_doc())
    assert rep.ok, rep.to_dict()
    assert design.block_count == 3
    assert design.dimensions == (2, 1, 2)


def test_bad_version():
    d = base_doc()
    d["schemaVersion"] = 2
    _, rep = parse_and_validate(d)
    assert any(i.code == "schemaVersion" for i in rep.errors)


def test_bad_format():
    d = base_doc()
    d["format"] = "other"
    _, rep = parse_and_validate(d)
    assert any(i.code == "format" for i in rep.errors)


def test_out_of_bounds_coord():
    d = base_doc()
    d["blocks"].append({"x": 7, "y": 0, "z": 0, "paletteIndex": 0})
    _, rep = parse_and_validate(d)
    assert any(i.code == "blocks.bounds" for i in rep.errors)


def test_bad_palette_index():
    d = base_doc()
    d["blocks"][0]["paletteIndex"] = 42
    _, rep = parse_and_validate(d)
    assert any(i.code == "blocks.paletteIndex" for i in rep.errors)


def test_duplicate_coord():
    d = base_doc()
    d["blocks"].append(dict(d["blocks"][0]))
    _, rep = parse_and_validate(d)
    assert any(i.code == "blocks.duplicate" for i in rep.errors)


def test_duplicate_palette_merged():
    d = base_doc()
    d["palette"].append({"id": "minecraft:stone", "states": {}})
    design, rep = parse_and_validate(d)
    assert rep.ok
    assert len(design.palette) == 1  # merged
    assert {b.palette_index for b in design.blocks} == {0}
    assert any(i.code == "palette.duplicate" for i in rep.warnings)


def test_bad_block_id():
    d = base_doc()
    d["palette"][0]["id"] = "stone_without_namespace"
    _, rep = parse_and_validate(d)
    assert any(i.code == "palette.id" for i in rep.errors)


def test_negative_dimension():
    d = base_doc()
    d["dimensions"]["x"] = 0
    _, rep = parse_and_validate(d)
    assert any(i.code == "dimensions.range" for i in rep.errors)


def test_huge_dimension_rejected():
    d = base_doc()
    d["dimensions"]["x"] = MAX_DIMENSION + 1
    _, rep = parse_and_validate(d)
    assert any(i.code == "dimensions.range" for i in rep.errors)


def test_states_types():
    d = base_doc()
    d["palette"][0]["states"] = {"toggle_bit": True, "count": 3, "kind": "oak"}
    design, rep = parse_and_validate(d)
    assert rep.ok
    st = dict(design.palette[0].states)
    assert st == {"toggle_bit": True, "count": 3, "kind": "oak"}


def test_state_float_rejected():
    d = base_doc()
    d["palette"][0]["states"] = {"count": 1.5}
    _, rep = parse_and_validate(d)
    assert any(i.code == "palette.state" for i in rep.errors)


def test_layer_bounds_and_rooms():
    d = base_doc()
    d["dimensions"] = {"x": 4, "y": 4, "z": 4}
    d["blocks"] = [{"x": x, "y": y, "z": z, "paletteIndex": 0}
                   for x in range(4) for y in range(4) for z in range(4)]
    d["layers"] = [{"id": "l1", "yMin": 0, "yMax": 1},
                   {"id": "l2", "yMin": 2, "yMax": 9}]
    d["rooms"] = [{"id": "r1", "bounds": {"x0": 0, "z0": 0, "x1": 3, "z1": 3},
                   "layerId": "ghost-layer"}]
    design, rep = parse_and_validate(d)
    assert any(i.code == "layers.range" for i in rep.errors)   # yMax 9 > height
    assert any(i.code == "rooms.layer" for i in rep.warnings)   # unknown layer


def test_truncated_json_parse_error():
    with pytest.raises(ParseError):
        load_json_bytes(b'{"format": "schematic3d-build", ')


def test_json_bom_ok():
    data = ("\ufeff" + json.dumps(base_doc())).encode("utf-8")
    doc = load_json_bytes(data)
    assert doc["format"] == "schematic3d-build"


def test_schema_check_catches_shape():
    d = base_doc()
    d["extraKey"] = 1
    msgs = schema_check(d)
    assert any("extraKey" in m for m in msgs)


def test_roundtrip_export_load(examples_dir):
    from schematic3d_converter.exporters.schematic3d_out import (
        to_bytes, load_design_dict)
    from schematic3d_converter.validate import parse_and_validate
    p = examples_dir / "cottage-12x8x12.json"
    design, rep = parse_and_validate(json.loads(p.read_text(encoding="utf-8")))
    assert rep.ok
    data = to_bytes(design)
    again = json.loads(data.decode("utf-8"))
    d2, rep2 = parse_and_validate(again)
    assert rep2.ok
    assert d2.block_count == design.block_count
    assert d2.to_json_dict() == design.to_json_dict()
