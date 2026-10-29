"""Schematic 3D converter package.

Parsers (external → internal `schematic3d-build`):
- parsers.schematic3d_json : JSON (with validation)
- parsers.mcstructure      : Bedrock .mcstructure (little-endian NBT)
- parsers.litematic        : Java Litematica .schem (big-endian gzip NBT)
- parsers.sponge           : legacy MCEdit .schematic (big-endian gzip NBT)

Exporters (internal → external):
- exporters.mcstructure_out : Bedrock .mcstructure (for structure packs)
- exporters.addon_pack      : builds .mcaddon zips embedding designs for the
                              Schematic 3D Builder behaviour pack
"""
from .models import Design, PaletteEntry, BlockEntry, Layer, Room  # noqa: F401
from .validate import parse_and_validate, ValidationReport, Issue  # noqa: F401
from .resources import material_summary, MaterialRow  # noqa: F401

__version__ = "1.0.0"
