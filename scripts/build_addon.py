#!/usr/bin/env python3
"""Build dist artifacts:

  dist/Schematic3DBuilder-base.mcaddon     empty template (UI + blocks)
  dist/Schematic3DBuilder.mcaddon          with the three example designs
                                           baked in (JSON + .mcstructure)
Usage: python3 scripts/build_addon.py [--version 1.0.0]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "converter" / "src"))

from schematic3d_converter.exporters.addon_pack import bake  # noqa: E402

DESIGNS = [
    ("cottage12x8x12", "examples/cottage-12x8x12.json"),
    ("tower9x18x9", "examples/tower-9x18x9.json"),
    ("archbridge21x9x7", "examples/arch-bridge-21x9x7.json"),
]


def parse_version(text: str) -> tuple[int, int, int]:
    parts = [int(x) for x in text.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])  # type: ignore[return-value]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="1.0.0")
    args = ap.parse_args(argv)
    ver = parse_version(args.version)

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)

    base = bake(ROOT / "bedrock_addon", [], dist / "_base", pack_version=ver)
    (dist / "Schematic3DBuilder-base.mcaddon").write_bytes(base.read_bytes())
    print("built dist/Schematic3DBuilder-base.mcaddon")

    with_designs = bake(
        ROOT / "bedrock_addon",
        [(hid, ROOT / rel) for hid, rel in DESIGNS],
        dist / "_full",
        pack_version=ver,
    )
    (dist / "Schematic3DBuilder.mcaddon").write_bytes(with_designs.read_bytes())
    print("built dist/Schematic3DBuilder.mcaddon with", len(DESIGNS), "designs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
