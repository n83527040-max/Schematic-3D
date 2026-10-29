"""Internal-format JSON parser: file → dict → (Design, report).

Schema validation uses `jsonschema` when available, else falls back to the
built-in structural checks (which are always run regardless, because they
also produce the semantic issues). The original document is returned so the
caller can preserve it byte-for-byte on failure paths.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ..models import FORMAT_ID
from ..validate import parse_and_validate, ValidationReport


class ParseError(Exception):
    def __init__(self, message: str, raw: bytes | None = None):
        super().__init__(message)
        self.raw = raw


def load_json_bytes(data: bytes) -> dict:
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ParseError(f"file is not valid utf-8: {exc}", data) from exc
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ParseError(f"invalid JSON at line {exc.lineno} col {exc.colno}: "
                         f"{exc.msg}", data) from exc
    if not isinstance(doc, dict):
        raise ParseError("top level JSON value must be an object", data)
    return doc


def schema_check(doc: dict) -> list[str]:
    """Run JSON-Schema validation if the dependency exists. Returns messages."""
    try:
        import jsonschema  # type: ignore
    except ImportError:
        return []
    schema_path = Path(__file__).resolve().parents[3] / "schemas" / \
        "schematic3d-build.v1.schema.json"
    if not schema_path.exists():
        return []
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)
    msgs = []
    for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.path)):
        loc = "$" + "".join(f"[{p!r}]" for p in err.path)
        msgs.append(f"schema {loc}: {err.message}")
    return msgs


def parse_file(path: Path, *, id_check=None) -> tuple[dict, Any, ValidationReport]:
    """Returns (raw_doc, design|None, report)."""
    data = path.read_bytes()
    doc = load_json_bytes(data)
    report = ValidationReport()
    for msg in schema_check(doc):
        report.error("schema", msg)
    design, rep2 = parse_and_validate(doc, id_check=id_check)
    rep2.issues = report.issues + rep2.issues
    return doc, design, rep2


def parse_bytes(data: bytes, *, id_check=None) -> tuple[dict, Any, ValidationReport]:
    doc = load_json_bytes(data)
    design, rep = parse_and_validate(doc, id_check=id_check)
    for msg in schema_check(doc):
        rep.issues.insert(0, _issue(msg))
    return doc, design, rep


def _issue(msg: str):
    from ..validate import Issue
    return Issue("error", "schema", msg)
