#!/usr/bin/env python3
"""Sync the Bedrock add-on template into app assets.

The app bundles the SAME pack sources that `scripts/build_addon.py` builds,
so an in-app .mcaddon export is byte-comparable to the desktop pipeline
(plus the embedded designs). Run after changing bedrock_addon/ and commit
the result so CI can build the APK without repo cross-links.

Usage: python3 app/tool/sync_addon_template.py
"""
from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_BP = ROOT / "bedrock_addon" / "behavior_pack"
SRC_RP = ROOT / "bedrock_addon" / "resource_pack"
DST = ROOT / "app" / "assets" / "addon_template"

KEEP_SUFFIXES = {
    ".json", ".js", ".png", ".lang", ".mcstructure", ".md", ".txt",
}


def copy_pack(src: Path, dst: Path) -> int:
    n = 0
    for f in sorted(src.rglob("*")):
        if not f.is_file():
            continue
        if f.suffix.lower() not in KEEP_SUFFIXES:
            continue
        if f.name == "package.json":  # dev-only (node tests)
            continue
        rel = f.relative_to(src)
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, out)
        n += 1
    return n


def main() -> int:
    if DST.exists():
        shutil.rmtree(DST)
    bp = copy_pack(SRC_BP, DST / "bp")
    rp = copy_pack(SRC_RP, DST / "rp")
    # shared tint vectors used by golden tests
    shutil.copy2(ROOT / "bedrock_addon" / "shared" / "tint_vectors.json",
                 ROOT / "app" / "assets" / "generated" / "tint_vectors.json")
    print(f"addon template synced: bp={bp} files, rp={rp} files -> app/assets/addon_template")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
