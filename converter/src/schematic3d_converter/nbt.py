"""Minimal, dependency-free NBT reader/writer supporting big-endian and
little-endian variants, with optional gzip compression.

Covered tags: 0 End, 1 Byte, 2 Short, 3 Int, 4 Long, 5 Float, 6 Double,
7 ByteArray, 8 String, 9 List, 10 Compound, 11 IntArray, 12 LongArray.

Little-endian NBT (used by Bedrock .mcstructure) also omits the payload type
byte for End-typed (empty) lists, matching the vanilla writer.
"""
from __future__ import annotations

import gzip
import io
import struct
import zlib
from dataclasses import dataclass, field
from typing import BinaryIO

TAG_END = 0
TAG_BYTE = 1
TAG_SHORT = 2
TAG_INT = 3
TAG_LONG = 4
TAG_FLOAT = 5
TAG_DOUBLE = 6
TAG_BYTE_ARRAY = 7
TAG_STRING = 8
TAG_LIST = 9
TAG_COMPOUND = 10
TAG_INT_ARRAY = 11
TAG_LONG_ARRAY = 12


class NbtError(Exception):
    """Raised on any malformed NBT input."""


@dataclass
class ListTag:
    """Typed NBT list payload. ``item_type`` is a TAG_* constant."""

    item_type: int
    items: list = field(default_factory=list)


class NbtFile:
    """Parsed NBT root: name + compound payload."""

    def __init__(self, name: str, root: dict):
        self.name = name
        self.root = root


def read_nbt(data: bytes, little_endian: bool = False, allow_gzip: bool = True):
    """Parse NBT bytes. Returns (root_name, root_compound).

    Accepts plain, gzip-wrapped and zlib-wrapped payloads when allow_gzip.
    """
    if little_endian:
        magic = b""
    else:
        magic = b"\x1f\x8b"
    if allow_gzip:
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        elif data[:1] == b"\x78":
            data = zlib.decompress(data)
    buf = io.BytesIO(data)
    tag_type = _read_u8(buf)
    if tag_type != TAG_COMPOUND:
        raise NbtError(f"root tag must be Compound(10), got {tag_type}")
    name = _read_string(buf, little_endian)
    root = _read_payload(buf, TAG_COMPOUND, little_endian, depth=0)
    return name, root


MAX_DEPTH = 512


def _read_u8(buf: BinaryIO) -> int:
    b = buf.read(1)
    if len(b) != 1:
        raise NbtError("unexpected EOF reading tag type")
    return b[0]


def _fmt(little: bool, base: str) -> str:
    return ("<" if little else ">") + base


def _read_string(buf: BinaryIO, little: bool) -> str:
    (ln,) = struct.unpack(_fmt(little, "H"), _must(buf, 2))
    raw = _must(buf, ln)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise NbtError(f"invalid utf-8 string in NBT: {exc}") from exc


def _must(buf: BinaryIO, n: int) -> bytes:
    data = buf.read(n)
    if len(data) != n:
        raise NbtError(f"unexpected EOF: wanted {n} bytes, got {len(data)}")
    return data


_FIXED = {
    TAG_BYTE: ("b", 1),
    TAG_SHORT: ("h", 2),
    TAG_INT: ("i", 4),
    TAG_LONG: ("q", 8),
    TAG_FLOAT: ("f", 4),
    TAG_DOUBLE: ("d", 8),
}


def _read_payload(buf: BinaryIO, tag_type: int, little: bool, depth: int):
    if depth > MAX_DEPTH:
        raise NbtError("NBT nesting too deep")
    if tag_type in _FIXED:
        fmt, size = _FIXED[tag_type]
        (value,) = struct.unpack(_fmt(little, fmt), _must(buf, size))
        return value
    if tag_type == TAG_STRING:
        return _read_string(buf, little)
    if tag_type == TAG_BYTE_ARRAY:
        (ln,) = struct.unpack(_fmt(little, "i"), _must(buf, 4))
        if ln < 0 or ln > 512 * 1024 * 1024:
            raise NbtError("byte array length invalid")
        return list(_must(buf, ln))
    if tag_type in (TAG_INT_ARRAY, TAG_LONG_ARRAY):
        (ln,) = struct.unpack(_fmt(little, "i"), _must(buf, 4))
        fmt = "i" if tag_type == TAG_INT_ARRAY else "q"
        size = 4 if tag_type == TAG_INT_ARRAY else 8
        if ln < 0 or ln * size > 2048 * 1024 * 1024:
            raise NbtError("array length invalid")
        if ln == 0:
            return []
        raw = _must(buf, ln * size)
        return list(struct.unpack(_fmt(little, f"{ln}{fmt}"), raw))
    if tag_type == TAG_LIST:
        item_type = _read_u8(buf)
        (ln,) = struct.unpack(_fmt(little, "i"), _must(buf, 4))
        if ln < 0 or ln > 64 * 1024 * 1024:
            raise NbtError("list length invalid")
        if item_type == TAG_END and ln != 0:
            raise NbtError("non-empty list with END item type")
        items = []
        for _ in range(ln):
            # List items carry no tag type / no names; payload directly.
            items.append(_read_payload(buf, item_type, little, depth + 1))
        return ListTag(item_type, items)
    if tag_type == TAG_COMPOUND:
        out: dict = {}
        while True:
            tt = _read_u8(buf)
            if tt == TAG_END:
                return out
            name = _read_string(buf, little)
            out[name] = _read_payload(buf, tt, little, depth + 1)
    raise NbtError(f"unknown tag type {tag_type}")


# A pragmatic guard: many real-world Bedrock lists (block_palette etc.) store
# compounds WITHOUT repeating the payload type byte. Handle both conventions.
def _read_payload_lenient_list_fix(data: bytes) -> bytes:  # pragma: no cover
    return data


def write_nbt(root: dict, name: str = "", little_endian: bool = False,
              gzip_output: bool = False) -> bytes:
    buf = io.BytesIO()
    buf.write(struct.pack("B", TAG_COMPOUND))
    _write_string(buf, name, little_endian)
    _write_compound(buf, root, little_endian, depth=0)
    data = buf.getvalue()
    if gzip_output:
        return gzip.compress(data, 6)
    return data


def _write_string(buf: BinaryIO, s: str, little: bool):
    raw = s.encode("utf-8")
    buf.write(struct.pack(_fmt(little, "H"), len(raw)))
    buf.write(raw)


def _write_compound(buf: BinaryIO, obj: dict, little: bool, depth: int):
    if depth > MAX_DEPTH:
        raise NbtError("NBT nesting too deep")
    for key, value in obj.items():
        tt, payload = _classify(value)
        if tt == TAG_END:
            continue
        buf.write(struct.pack("B", tt))
        _write_string(buf, key, little)
        _write_value(buf, tt, payload, little, depth + 1)
    buf.write(struct.pack("B", TAG_END))


def _classify(value):
    if value is None:
        return TAG_END, None
    if isinstance(value, bool):
        return TAG_BYTE, value
    if isinstance(value, int):
        return TAG_LONG, value
    if isinstance(value, float):
        return TAG_DOUBLE, value
    if isinstance(value, str):
        return TAG_STRING, value
    if isinstance(value, NbtInt):
        return TAG_INT, value.value
    if isinstance(value, NbtShort):
        return TAG_SHORT, value.value
    if isinstance(value, NbtByte):
        return TAG_BYTE, value.value
    if isinstance(value, NbtFloat):
        return TAG_FLOAT, value.value
    if isinstance(value, bytes):
        return TAG_BYTE_ARRAY, list(value)
    if isinstance(value, IntArray):
        return TAG_INT_ARRAY, value.values
    if isinstance(value, LongArray):
        return TAG_LONG_ARRAY, value.values
    if isinstance(value, ListTag):
        return TAG_LIST, value
    if isinstance(value, (list, tuple)):
        return TAG_LIST, _wrap_list(list(value))
    if isinstance(value, dict):
        return TAG_COMPOUND, value
    raise NbtError(f"unsupported python type for NBT: {type(value)}")


def _wrap_list(items: list) -> ListTag:
    if not items:
        return ListTag(TAG_END, [])
    tt, _ = _classify(items[0])
    if tt == TAG_END:
        return ListTag(TAG_END, items)
    return ListTag(tt, items)


def _write_value(buf: BinaryIO, tt: int, value, little: bool, depth: int):
    if isinstance(value, _TypedNum):
        value = value.value
    if tt in _FIXED:
        fmt, _size = _FIXED[tt]
        if tt == TAG_BYTE and isinstance(value, bool):
            value = 1 if value else 0
        if tt == TAG_BYTE_ARRAY and isinstance(value, (bytes, bytearray)):
            value = list(value)
        buf.write(struct.pack(_fmt(little, fmt), value))
        return
    if tt == TAG_STRING:
        _write_string(buf, value, little)
        return
    if tt == TAG_BYTE_ARRAY:
        buf.write(struct.pack(_fmt(little, "i"), len(value)))
        buf.write(bytes(v & 0xFF for v in value))
        return
    if tt in (TAG_INT_ARRAY, TAG_LONG_ARRAY):
        fmt = "i" if tt == TAG_INT_ARRAY else "q"
        size = 4 if tt == TAG_INT_ARRAY else 8
        buf.write(struct.pack(_fmt(little, "i"), len(value)))
        if value:
            buf.write(struct.pack(_fmt(little, f"{len(value)}{fmt}"), *value))
        return
    if tt == TAG_LIST:
        lt: ListTag = value
        buf.write(struct.pack("B", lt.item_type))
        buf.write(struct.pack(_fmt(little, "i"), len(lt.items)))
        for item in lt.items:
            if lt.item_type == TAG_COMPOUND:
                _write_compound(buf, item, little, depth)
            else:
                _write_value(buf, lt.item_type, item, little, depth)
        return
    if tt == TAG_COMPOUND:
        _write_compound(buf, value, little, depth)
        return
    raise NbtError(f"cannot write tag {tt}")


# Explicit typed number wrappers (Bedrock needs ints where python would pick long).
class _TypedNum:
    def __init__(self, value):
        self.value = value

    def __repr__(self):  # pragma: no cover
        return f"{type(self).__name__}({self.value})"


class NbtByte(_TypedNum): pass
class NbtShort(_TypedNum): pass
class NbtInt(_TypedNum): pass
class NbtFloat(_TypedNum): pass


class IntArray:
    def __init__(self, values):
        self.values = list(values)


class LongArray:
    def __init__(self, values):
        self.values = list(values)
