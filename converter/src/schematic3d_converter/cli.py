"""`s3dc` command line interface.

Commands:
  s3dc validate FILE                structural + semantic validation
  s3dc convert IN OUT[.json|.mcstructure]  conversion with report
  s3dc materials IN                 material table (json)
  s3dc block-catalog OUT.json       emit shared block catalog asset
  s3dc build-addon DIR|--designs ... OUT.mcaddon
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .ids import snapshot_json, write_snapshot
from .parsers.any import load_any
from .report import build_report, file_sha256


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="s3dc",
                                 description="Schematic 3D converter toolset")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("validate", help="validate any supported design file")
    p.add_argument("file")
    p.add_argument("--json", action="store_true", help="machine-readable output")

    p = sub.add_parser("convert", help="convert design file → json / mcstructure")
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--report", help="write conversion report JSON here")
    p.add_argument("--pretty", action="store_true")

    p = sub.add_parser("materials", help="print material summary as JSON")
    p.add_argument("file")

    p = sub.add_parser("block-catalog", help="emit shared block catalog json")
    p.add_argument("output")

    p = sub.add_parser("build-addon", help="package designs into an .mcaddon")
    p.add_argument("--addon-dir", help="addon template dir (behavior_pack, resource_pack)")
    p.add_argument("--designs", nargs="*", default=[], help="design files (any format)")
    p.add_argument("output")

    args = ap.parse_args(argv)
    try:
        return _dispatch(args)
    except Exception as exc:  # user-facing errors exit 2
        print(f"error: {exc}", file=sys.stderr)
        return 2


def _dispatch(args) -> int:
    if args.cmd == "validate":
        from .ids import check_id
        design, rep, conv, fmt = load_any(Path(args.file), json_id_check=check_id)
        out = {
            "file": str(args.file),
            "format": fmt,
            "design": design.name,
            "dimensions": list(design.dimensions),
            "blockCount": design.block_count,
            "report": rep.to_dict(),
        }
        print(json.dumps(out, ensure_ascii=False, indent=1))
        return 0 if rep.ok else 1

    if args.cmd == "convert":
        from .ids import check_id
        src = Path(args.input)
        original_sha = file_sha256(src)
        design, rep, conv, fmt = load_any(src, json_id_check=check_id)
        if not rep.ok:
            print(json.dumps({"ok": False, "report": rep.to_dict()},
                             ensure_ascii=False, indent=1), file=sys.stderr)
            print("original file left untouched", file=sys.stderr)
            return 1
        out = Path(args.output)
        # preserve original file semantics: we never overwrite the input.
        if out.resolve() == src.resolve():
            out = out.with_suffix(".converted" + out.suffix)
        if out.suffix == ".mcstructure":
            from .exporters.mcstructure_out import write_file
            write_file(design, out)
        else:
            from .exporters.schematic3d_out import write_file as wj
            wj(design, out.with_suffix(".json"), pretty=args.pretty)
            out = out.with_suffix(".json")
        if args.report:
            rpt = build_report(design, fmt=fmt, rep=rep, conv=conv)
            Path(args.report).write_text(rpt.to_json(), encoding="utf-8")
        print(json.dumps({"ok": True, "output": str(out), "sha256Input": original_sha,
                          "blocks": design.block_count}, ensure_ascii=False))
        return 0

    if args.cmd == "materials":
        from .resources import material_summary
        design, rep, conv, fmt = load_any(Path(args.file))
        if not rep.ok:
            print(json.dumps({"ok": False, "report": rep.to_dict()}, indent=1),
                  file=sys.stderr)
            return 1
        print(json.dumps(material_summary(design).to_dict(), ensure_ascii=False,
                         indent=1))
        return 0

    if args.cmd == "block-catalog":
        p = Path(args.output)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(snapshot_json(), ensure_ascii=False, indent=1),
                     encoding="utf-8")
        print(f"wrote {p}")
        return 0

    if args.cmd == "build-addon":
        from .exporters.addon_pack import build_mcaddon
        out = build_mcaddon(
            addon_dir=Path(args.addon_dir) if args.addon_dir else None,
            designs=[Path(d) for d in args.designs],
            out_path=Path(args.output),
        )
        print(f"wrote {out}")
        return 0

    return 2


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
