"""Conversion report assembly (what changed, what was dropped)."""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

from .models import Design
from .resources import material_summary
from .validate import ValidationReport


@dataclass
class ConversionReport:
    input_format: str
    design_name: str
    dimensions: tuple[int, int, int]
    block_count: int
    palette_size: int
    validation: dict
    mapping: list[dict] = field(default_factory=list)
    dropped_blocks: int = 0
    materials: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "inputFormat": self.input_format,
            "designName": self.design_name,
            "dimensions": {"x": self.dimensions[0], "y": self.dimensions[1],
                           "z": self.dimensions[2]},
            "blockCount": self.block_count,
            "paletteSize": self.palette_size,
            "droppedBlocks": self.dropped_blocks,
            "mappingEntries": self.mapping,
            "validation": self.validation,
            "materials": self.materials,
            "conversionComplete": self.dropped_blocks == 0
            and not [i for i in self.validation.get("issues", [])
                     if i["level"] == "error"],
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), ensure_ascii=False, indent=1)


def build_report(design: Design, *, fmt: str, rep: ValidationReport,
                 conv: dict | None) -> ConversionReport:
    ms = material_summary(design)
    return ConversionReport(
        input_format=fmt,
        design_name=design.name,
        dimensions=design.dimensions,
        block_count=design.block_count,
        palette_size=len(design.palette),
        validation=rep.to_dict(),
        mapping=(conv or {}).get("entries", []),
        dropped_blocks=(conv or {}).get("droppedBlocks", 0),
        materials=ms.to_dict(),
    )


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()
