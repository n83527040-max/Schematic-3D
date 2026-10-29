#!/usr/bin/env python3
"""Structural validator for a built .mcaddon (offline QA gate for CI).

Checks:
  - valid zip, both packs present with manifests at pack roots
  - all embedded JSON parse and follow the expected schema bits
  - UUIDs unique across packs, versions are [maj,min,pat]
  - min_engine_version allows 1.26.40 (target) and module deps pin
    @minecraft/server 2.10.0-beta + @minecraft/server-ui 2.2.0-beta
  - script entry exists; every `import` in scripts resolves to a file in the
    zip (local modules only — no path traversal, no external scripts)
  - design data modules parse as JSON payload and block indices are within
    bounds (semantic sample check)
Exit 0 on success, prints PASS/FAIL lines.
"""
from __future__ import annotations

import json
import re
import sys
import zipfile
from pathlib import Path

IMPORT_RE = re.compile(r"from\s+[\"'](\./[^\"']+|\.\./[^\"']+\.[a-z]+)[\"']")
DESIGN_RE = re.compile(r"export const DESIGN = (\{.*\});", re.S)


def check(cond: bool, label: str, failures: list[str]):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label}")
    if not cond:
        failures.append(label)


def main(path: Path) -> int:
    failures: list[str] = []
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        packs = sorted({n.split("/")[0] for n in names if "/" in n})
        check(len(packs) == 2, f"two top-level packs found: {packs}", failures)

        manifests = {}
        for pack in packs:
            mname = f"{pack}/manifest.json"
            check(mname in names, f"{mname} exists", failures)
            manifests[pack] = json.loads(z.read(mname).decode("utf-8"))

        uuids: list[str] = []
        for pack, mf in manifests.items():
            uuids.append(mf["header"]["uuid"])
            for mod in mf["modules"]:
                uuids.append(mod["uuid"])
        check(len(set(uuids)) == len(uuids), "all UUIDs unique", failures)
        for u in uuids:
            check(bool(re.match(
                r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", u)),
                f"uuid format ok: {u}", failures)

        bp_key = next(p for p in packs if "bp" in p)
        bp = manifests[bp_key]
        check(bp["header"].get("min_engine_version") == [1, 26, 40],
              "BP min_engine_version == [1,26,40]", failures)
        deps = {d.get("module_name"): d.get("version")
                for d in bp.get("dependencies", []) if "module_name" in d}
        check(deps.get("@minecraft/server") == "2.10.0-beta",
              "BP depends @minecraft/server 2.10.0-beta", failures)
        check(deps.get("@minecraft/server-ui") == "2.2.0-beta",
              "BP depends @minecraft/server-ui 2.2.0-beta", failures)

        script_mod = next((m for m in bp["modules"] if m["type"] == "script"), None)
        check(script_mod is not None, "script module declared", failures)
        if script_mod:
            entry = f"{bp_key}/{script_mod['entry']}"
            check(entry in names, f"entry {entry} present", failures)

        # JSON files all parse
        bad_json = []
        for n in names:
            if n.endswith(".json"):
                try:
                    json.loads(z.read(n).decode("utf-8"))
                except Exception as exc:
                    bad_json.append(f"{n}: {exc}")
        check(not bad_json, f"all JSON files parse ({bad_json[:2]})", failures)

        # import graph of scripts stays inside the pack
        missing_imports = []
        script_files = [n for n in names if n.endswith(".js")]
        for n in script_files:
            text = z.read(n).decode("utf-8")
            for imp in IMPORT_RE.findall(text):
                base = (Path(n).parent / imp).resolve()
                rel = str(base.relative_to("/") if base.is_absolute() else base)
                rel = rel.strip("/")
                check_ok = rel in names or f"{rel}.js" in names
                # relative dot segments normalization
                norm = "/".join(str(Path(rel).resolve()).split("/"))
                if not check_ok:
                    target = n[: n.rindex("/")] + "/" + imp
                    parts = []
                    for part in target.split("/"):
                        if part == "..":
                            parts.pop()
                        elif part != ".":
                            parts.append(part)
                    cand = "/".join(parts)
                    check_ok = cand in names or f"{cand}.js" in names
                if not check_ok:
                    missing_imports.append(f"{n} → {imp}")
        check(not missing_imports,
              f"all local imports resolve in-pack ({missing_imports[:3]})", failures)

        check(all(".." not in n for n in names), "no path traversal in zip entries",
              failures)

        # designs sample-check
        data_files = [n for n in names if "/scripts/s3d/data/design_" in n
                      or re.search(r"/scripts/s3d/data/[a-z0-9_]+\.js$", n)]
        design_json = [n for n in names if n.endswith("scripts/s3d/data/manifest.json")]
        if design_json:
            data = json.loads(z.read(design_json[0]).decode("utf-8"))
            check(all(d["id"] for d in data["designs"]), "designs manifest ids present",
                  failures)
            checked = 0
            for item in data["designs"]:
                mod = next((n for n in data_files if n.endswith(f'{item["module"].lstrip("./")}')), None)
                if not mod:
                    check(False, f"design module file for {item['id']} present", failures)
                    continue
                m = DESIGN_RE.search(z.read(mod).decode("utf-8"))
                if not m:
                    check(False, f"design {item['id']} payload parse", failures)
                    continue
                doc = json.loads(m.group(1))
                dx, dy, dz = (doc["dimensions"][k] for k in "xyz")
                inb = all(0 <= b["x"] < dx and 0 <= b["y"] < dy and 0 <= b["z"] < dz
                          and 0 <= b["paletteIndex"] < len(doc["palette"])
                          for b in doc["blocks"])
                check(inb, f"design {item['id']}: all indices in bounds", failures)
                checked += 1
            print(f"[info] designs embedded: {checked}")

    print()
    if failures:
        print(f"RESULT: FAIL ({len(failures)} problems)")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: validate_addon.py PATH.mcaddon", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(Path(sys.argv[1])))
