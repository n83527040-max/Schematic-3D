"""Export of internal Design to `schematic3d-build` JSON."""
from __future__ import annotations

import json
from pathlib import Path

from ..models import Design


def write_file(design: Design, path: Path, *, pretty: bool = False) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(design.to_json(pretty=pretty), encoding="utf-8")
    return path


def to_bytes(design: Design) -> bytes:
    return design.to_json().encode("utf-8")


def load_design_dict(path: Path) -> Design:
    """Convenience: read a previously exported design back."""
    from ..validate import parse_and_validate
    doc = json.loads(path.read_text(encoding="utf-8"))
    design, rep = parse_and_validate(doc)
    if not rep.ok:
        raise ValueError(f"design file invalid: {rep.to_dict()}")
    return design
