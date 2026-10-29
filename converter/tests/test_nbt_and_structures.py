"""NBT engine + structure format tests, including REAL Bedrock/Litematica
files (fixtures from the Bedrockmatika MIT catalog repo, see NOTICE)."""
from __future__ import annotations

import pytest

from schematic3d_converter.nbt import (ListTag, NbtError, NbtByte, NbtFloat,
                                       NbtInt, NbtShort, TAG_COMPOUND,
                                       TAG_INT, TAG_STRING, read_nbt,
                                       write_nbt)
from schematic3d_converter.parsers.mcstructure import (McstructureError,
                                                        parse_bytes as mc_parse)
from schematic3d_converter.parsers.sponge_v2 import parse_bytes as sponge2_parse
from schematic3d_converter.exporters.mcstructure_out import write_file as mc_write
from schematic3d_converter.models import BlockEntry, Design, Layer, PaletteEntry
from schematic3d_converter.ids import check_id


# ---------------------------------------------------------------- NBT ------

def test_nbt_roundtrip_both_endians():
    payload = {
        "int": NbtInt(7),
        "short": NbtShort(-3),
        "byte": NbtByte(1),
        "float": NbtFloat(1.5),
        "str": "مرحبا hello",
        "listInt": ListTag(TAG_INT, [NbtInt(1), NbtInt(2), NbtInt(3)]),
        "listStr": ListTag(TAG_STRING, ["a", "b"]),
        "nested": {"deep": {"x": NbtInt(1)}},
        "listComp": ListTag(TAG_COMPOUND, [{"k": NbtInt(1)}, {"k": NbtInt(2)}]),
    }
    for little in (False, True):
        blob = write_nbt(payload, name="root", little_endian=little)
        _, back = read_nbt(blob, little_endian=little)
        assert back["int"] == 7 and back["str"] == "مرحبا hello"
        assert [x for x in back["listInt"].items] == [1, 2, 3]
        assert back["nested"]["deep"]["x"] == 1
        assert len(back["listComp"].items) == 2


def test_nbt_rejects_garbage():
    with pytest.raises(NbtError):
        read_nbt(b"\x0a\x00\x05hello", little_endian=False)  # truncated compound
    with pytest.raises(NbtError):
        read_nbt(b"\x09\x00\x00\xff\xff\xff\xff\xff\xff\xff\xff", little_endian=False)


# ------------------------------------------------------ real mcstructure ---

def test_real_forest_tower_parses(fixtures_dir):
    data = (fixtures_dir / "forest-tower.mcstructure").read_bytes()
    design, rep = mc_parse(data, source_name="forest-tower")
    assert rep.ok
    assert design.dimensions == (17, 19, 17)
    assert design.block_count > 800
    assert all(check_id(p.id) in ("known", "unknown") for p in design.palette)
    coords = {b.key() for b in design.blocks}
    assert len(coords) == len(design.blocks)  # no duplicates


def test_mcstructure_roundtrip_semantics(fixtures_dir, tmp_path):
    data = (fixtures_dir / "forest-tower.mcstructure").read_bytes()
    d1, _ = mc_parse(data, source_name="t")
    p = tmp_path / "t.mcstructure"
    mc_write(d1, p)
    d2, rep2 = mc_parse(p.read_bytes(), source_name="t2")
    assert rep2.ok
    assert d1.dimensions == d2.dimensions
    assert d1.block_count == d2.block_count
    # exact coordinate↔palette-id equality
    m1 = {(b.x, b.y, b.z): d1.palette[b.palette_index] for b in d1.blocks}
    m2 = {(b.x, b.y, b.z): d2.palette[b.palette_index] for b in d2.blocks}
    assert m1 == m2


def test_mcstructure_rejects_truncated(fixtures_dir):
    data = (fixtures_dir / "forest-tower.mcstructure").read_bytes()
    with pytest.raises((McstructureError, NbtError)):
        mc_parse(data[: len(data) // 2], source_name="bad")
    with pytest.raises(McstructureError):
        mc_parse(b"", source_name="empty")


# ------------------------------------------------- real sponge v2 (.schem) -

def test_real_bridge_sponge2(fixtures_dir):
    data = (fixtures_dir / "block-library-bridge.schem").read_bytes()
    design, rep, conv = sponge2_parse(data, source_name="bridge")
    assert rep.ok
    assert design.dimensions == (23, 10, 19)
    ids = {p.id for p in design.palette}
    assert "minecraft:grass" in ids  # java grass_block renamed to bedrock grass
    assert "minecraft:cherry_leaves" in ids
    assert conv["droppedBlocks"] == 0


def test_real_cabin_sponge2(fixtures_dir):
    data = (fixtures_dir / "block-library-cabin.schem").read_bytes()
    design, rep, conv = sponge2_parse(data, source_name="cabin")
    assert design.block_count > 1000
    seen = {b.key() for b in design.blocks}
    assert len(seen) == len(design.blocks)


# --------------------------------------------------------- generated -------

def test_generated_cottage_mcstructure_roundtrip(examples_dir, tmp_path):
    from schematic3d_converter.exporters.schematic3d_out import load_design_dict
    design = load_design_dict(examples_dir / "cottage-12x8x12.json")
    out = tmp_path / "cottage.mcstructure"
    mc_write(design, out)
    d2, rep = mc_parse(out.read_bytes(), source_name="cottage")
    assert rep.ok
    assert d2.block_count == design.block_count
    assert d2.dimensions == design.dimensions
