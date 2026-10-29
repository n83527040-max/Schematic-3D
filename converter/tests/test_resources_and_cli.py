"""Materials computed strictly from data + CLI smoke tests + addon packaging."""
from __future__ import annotations

import json

import pytest

from schematic3d_converter import material_summary
from schematic3d_converter.models import BlockEntry, Design, Layer, PaletteEntry
from schematic3d_converter.validate import parse_and_validate


def make_design():
    pal = [PaletteEntry.make("minecraft:stone"),
           PaletteEntry.make("minecraft:glass")]
    blocks = []
    for x in range(3):
        for z in range(3):
            blocks.append(BlockEntry(x, 0, z, 0))
    blocks.append(BlockEntry(1, 1, 1, 1))
    return Design(name="m", description=None, dimensions=(3, 2, 3),
                  palette=pal, blocks=blocks,
                  layers=[Layer("l1", None, 0, 0), Layer("l2", None, 1, 1)])


def test_material_counts_exact():
    ms = material_summary(make_design())
    total = {r.id: r.count for r in ms.rows}
    assert total == {"minecraft:stone": 9, "minecraft:glass": 1}
    assert ms.material_blocks == 10
    l1 = {r.id: r.count for r in ms.per_layer["l1"]}
    l2 = {r.id: r.count for r in ms.per_layer["l2"]}
    assert l1 == {"minecraft:stone": 9}
    assert l2 == {"minecraft:glass": 1}


def test_materials_not_from_text(examples_dir):
    """The count must come from blocks[] data, never from any description."""
    doc = json.loads((examples_dir / "cottage-12x8x12.json").read_text(encoding="utf-8"))
    doc["description"] = "يقول النص 9999 بلوك — يجب تجاهله"  # deliberately wrong
    design, rep = parse_and_validate(doc)
    assert rep.ok
    ms = material_summary(design)
    assert ms.total_blocks != 9999
    assert ms.total_blocks == len(doc["blocks"])


def test_cottage_materials_sum_matches_blocks(examples_dir):
    doc = json.loads((examples_dir / "cottage-12x8x12.json").read_text(encoding="utf-8"))
    design, _ = parse_and_validate(doc)
    ms = material_summary(design)
    assert sum(r.count for r in ms.rows) == ms.material_blocks == len(design.blocks)


# ----------------------------------------------------------------- CLI -----

def test_cli_validate_and_convert(examples_dir, tmp_path, capsys):
    from schematic3d_converter.cli import main
    rc = main(["validate", str(examples_dir / "cottage-12x8x12.json")])
    assert rc == 0
    out = json.loads(capsys.readouterr().out)
    assert out["blockCount"] > 0 and out["report"]["valid"]

    target = tmp_path / "converted.json"
    rc = main(["convert", str(examples_dir / "arch-bridge-21x9x7.json"),
               str(target), "--report", str(tmp_path / "report.json")])
    assert rc == 0
    res = json.loads(capsys.readouterr().out)
    assert res["ok"] and target.exists()
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert report["blockCount"] == 211
    assert report["conversionComplete"] is True


def test_cli_broken_inputs(examples_dir, tmp_path, capsys):
    from schematic3d_converter.cli import main
    rc = main(["validate", str(examples_dir / "broken-out-of-bounds.json")])
    assert rc == 1
    rc = main(["validate", str(examples_dir / "broken-truncated.json")])
    assert rc == 2  # parse error surfaces as exit 2
    rc = main(["validate", str(examples_dir / "broken-duplicate.json")])
    assert rc == 1


def test_cli_mcstructure_output(examples_dir, tmp_path, capsys):
    from schematic3d_converter.cli import main
    out = tmp_path / "c.mcstructure"
    rc = main(["convert", str(examples_dir / "tower-9x18x9.json"), str(out)])
    assert rc == 0
    capsys.readouterr()
    data = out.read_bytes()
    assert data[:1] == b"\x0a"
    from schematic3d_converter.parsers.mcstructure import parse_bytes
    d2, rep = parse_bytes(data, source_name="c")
    assert rep.ok and d2.dimensions == (9, 18, 9)


# ------------------------------------------------------- addon packaging ---

def test_build_addon_packages_designs(repo_root, examples_dir, tmp_path):
    from schematic3d_converter.exporters.addon_pack import bake
    mc = bake(
        addon_dir=repo_root / "bedrock_addon",
        designs=[("cottage12x8x12", examples_dir / "cottage-12x8x12.json")],
        out_dir=tmp_path,
    )
    assert mc.exists() and mc.suffix == ".mcaddon"
    import zipfile
    with zipfile.ZipFile(mc) as z:
        names = z.namelist()
        assert "s3d_builder_bp/scripts/s3d/data/cottage12x8x12.js" in names
        assert "s3d_builder_bp/scripts/s3d/data/index.js" in names
        index = z.read("s3d_builder_bp/scripts/s3d/data/index.js").decode()
        assert "DESIGNS" in index and "cottage12x8x12" in index.replace('"', "")
        manifest = json.loads(z.read("s3d_builder_bp/manifest.json"))
        assert manifest["header"]["min_engine_version"] == [1, 26, 40]
        dep_mods = {d.get("module_name"): d.get("version")
                    for d in manifest["dependencies"] if "module_name" in d}
        assert dep_mods["@minecraft/server"] == "2.10.0-beta"
        assert dep_mods["@minecraft/server-ui"] == "2.2.0-beta"


def test_broken_design_rejected_for_packaging(repo_root, examples_dir, tmp_path):
    from schematic3d_converter.exporters.addon_pack import bake
    with pytest.raises(ValueError):
        bake(addon_dir=repo_root / "bedrock_addon",
             designs=[("bad", examples_dir / "broken-out-of-bounds.json")],
             out_dir=tmp_path)
