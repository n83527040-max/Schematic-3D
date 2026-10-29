"""Format auto-detection entry point shared by CLI and tests."""
from __future__ import annotations

import gzip
import io
from pathlib import Path

from ..nbt import read_nbt
from . import litematic, mcstructure, schematic3d_json, sponge, sponge_v2


class UnsupportedFormat(Exception):
    pass


def load_any(path: Path, *, json_id_check=None):
    """Return (design, report, conversion_or_None, fmt_name).

    Detection is content-based (NBT roots), not extension-based, because users
    rename files constantly.
    """
    data = Path(path).read_bytes()
    fmt = sniff_format(data, path.suffix.lower())
    if fmt == "json":
        doc, design, rep = schematic3d_json.parse_file(
            Path(path), id_check=json_id_check)
        return design, rep, None, "json"
    if fmt == "mcstructure":
        design, rep = mcstructure.parse_bytes(data, source_name=Path(path).stem)
        return design, rep, None, "mcstructure"
    if fmt == "sponge2":
        design, rep, conv = sponge_v2.parse_bytes(data, source_name=Path(path).stem)
        return design, rep, conv, "sponge2"
    if fmt == "litematic":
        design, rep, conv = litematic.parse_bytes(data, source_name=Path(path).stem)
        return design, rep, conv, "litematic"
    if fmt == "schematic":
        design, rep = sponge.parse_bytes(data, source_name=Path(path).stem)
        return design, rep, None, "schematic"
    raise UnsupportedFormat(f"cannot detect a supported format for {path}")


def sniff_format(data: bytes, ext: str = "") -> str:
    if data[:2] == b"\x1f\x8b":
        try:
            payload = gzip.decompress(data[: 512 * 1024 * 1024])
        except Exception:
            payload = b""
    else:
        payload = data
    stripped = payload.lstrip(b"\xef\xbb\xbf").lstrip()
    if stripped[:1] == b"{":
        return "json"
    # NBT attempts ---------------------------------------------------------
    if len(payload) > 4 and payload[0] == 0x0A:
        # little-endian bedrock?
        try:
            name, root = read_nbt(payload, little_endian=True, allow_gzip=False)
            if "format_version" in root and "structure" in root:
                return "mcstructure"
        except Exception:
            pass
        try:
            name, root = read_nbt(payload, little_endian=False, allow_gzip=False)
            body = root.get("Schematic", root)
            if isinstance(body, dict):
                if body.get("Version") == 2 and "BlockData" in body:
                    return "sponge2"
                if "Regions" in body:
                    return "litematic"
                if "Materials" in body and "Blocks" in body:
                    return "schematic"
            if "Litematic" in root:
                return "litematic"
        except Exception:
            pass
    if ext == ".mcstructure":
        return "mcstructure"
    if ext == ".json":
        return "json"
    raise UnsupportedFormat("unrecognized file signature")
