/// Minimal NBT reader/writer (both endiannesses, optional gzip), covering
/// the tags Minecraft structure files use. Dart port of the reference
/// Python implementation; both are asserted on the same fixture files.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int tagEnd = 0;
const int tagByte = 1;
const int tagShort = 2;
const int tagInt = 3;
const int tagLong = 4;
const int tagFloat = 5;
const int tagDouble = 6;
const int tagByteArray = 7;
const int tagString = 8;
const int tagList = 9;
const int tagCompound = 10;
const int tagIntArray = 11;
const int tagLongArray = 12;

class NbtException implements Exception {
  NbtException(this.message);
  final String message;
  @override
  String toString() => 'NbtException: $message';
}

class NbtList {
  NbtList(this.itemType, this.items);
  final int itemType;
  final List<Object> items;

  List<Object?> toPlainList() => items.map(nbtUnwrap).toList(growable: false);
}

class NbtLong {
  const NbtLong(this.value);
  final int value;
}

class NbtInt {
  const NbtInt(this.value);
  final int value;
}

class NbtShort {
  const NbtShort(this.value);
  final int value;
}

class NbtByte {
  const NbtByte(this.value);
  final int value;
}

class NbtFloat {
  const NbtFloat(this.value);
  final double value;
}

Object? nbtUnwrap(Object? v) {
  if (v is NbtList) return v.items.map(nbtUnwrap).toList(growable: false);
  if (v is Map) return {for (final e in v.entries) e.key: nbtUnwrap(e.value)};
  if (v is NbtLong) return v.value;
  if (v is NbtInt) return v.value;
  if (v is NbtShort) return v.value;
  if (v is NbtByte) return v.value;
  if (v is NbtFloat) return v.value;
  return v;
}

class _Reader {
  _Reader(this.data, {required this.littleEndian})
      : byteData = ByteData.sublistView(data),
        pos = 0;
  final Uint8List data;
  final ByteData byteData;
  final bool littleEndian;
  int pos;

  int _u8() {
    if (pos >= data.length) throw NbtException('unexpected EOF');
    return data[pos++];
  }

  Endian get _end => littleEndian ? Endian.little : Endian.big;

  int _i16() => _take(2, (b, o) => b.getInt16(o, _end));
  int _i32() => _take(4, (b, o) => b.getInt32(o, _end));
  int _i64() => _take(8, (b, o) => b.getInt64(o, _end));
  double _f32() => _take(4, (b, o) => b.getFloat32(o, _end));
  double _f64() => _take(8, (b, o) => b.getFloat64(o, _end));

  T _take<T>(int n, T Function(ByteData, int) read) {
    if (pos + n > data.length) throw NbtException('unexpected EOF');
    final v = read(byteData, pos);
    pos += n;
    return v;
  }

  String readString() {
    final len = _u16();
    if (pos + len > data.length) throw NbtException('string EOF');
    final s = utf8.decode(data.sublist(pos, pos + len), allowMalformed: true);
    pos += len;
    return s;
  }

  int _u16() => _take(2, (b, o) => b.getUint16(o, _end));

  Map<String, Object?> readCompound(int depth) {
    if (depth > 512) throw NbtException('too deep');
    final out = <String, Object?>{};
    while (true) {
      final tt = _u8();
      if (tt == tagEnd) return out;
      final name = readString();
      out[name] = readPayload(tt, depth + 1);
    }
  }

  Object? readPayload(int tt, int depth) {
    switch (tt) {
      case tagByte:
        return NbtByte(_i8());
      case tagShort:
        return NbtShort(_i16());
      case tagInt:
        return NbtInt(_i32());
      case tagLong:
        return NbtLong(_i64());
      case tagFloat:
        return NbtFloat(_f32());
      case tagDouble:
        return _f64();
      case tagByteArray:
        final n = _i32();
        _checkLen(n, 1);
        final out = Uint8List(n);
        for (var i = 0; i < n; i++) {
          out[i] = _u8();
        }
        return out;
      case tagString:
        return readString();
      case tagList:
        final itemType = _u8();
        final n = _i32();
        if (n < 0 || n > 32 * 1024 * 1024) throw NbtException('list length invalid');
        if (itemType == tagEnd) {
          if (n != 0) throw NbtException('non-empty END-typed list');
          return NbtList(tagEnd, const []);
        }
        final items = <Object>[];
        for (var i = 0; i < n; i++) {
          if (itemType == tagCompound) {
            items.add(readCompound(depth + 1));
          } else {
            final v = readPayload(itemType, depth + 1);
            if (v == null) throw NbtException('null in list');
            items.add(v);
          }
        }
        return NbtList(itemType, items);
      case tagIntArray:
        final n = _i32();
        _checkLen(n, 4);
        return List<int>.generate(n, (_) => _i32(), growable: false);
      case tagLongArray:
        final n = _i32();
        _checkLen(n, 8);
        return List<int>.generate(n, (_) => _i64(), growable: false);
      default:
        throw NbtException('unknown tag type $tt');
    }
  }

  int _i8() => _take(1, (b, o) => b.getInt8(o));

  void _checkLen(int n, int size) {
    if (n < 0 || n * size > 1024 * 1024 * 512) {
      throw NbtException('array length invalid');
    }
  }
}

class NbtDoc {
  NbtDoc(this.rootName, this.root);
  final String rootName;
  final Map<String, Object?> root;
}

NbtDoc readNbt(Uint8List input, {required bool littleEndian, bool allowGzip = true}) {
  var data = input;
  if (allowGzip && data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
    data = Uint8List.fromList(gzip.decode(data));
  }
  final r = _Reader(data, littleEndian: littleEndian);
  final tt = r._u8();
  if (tt != tagCompound) throw NbtException('root must be Compound');
  final name = r.readString();
  final root = r.readCompound(0);
  return NbtDoc(name, root);
}

NbtDoc readNbtBytes(List<int> bytes, {required bool littleEndian}) =>
    readNbt(Uint8List.fromList(bytes), littleEndian: littleEndian);

// ------------------------------------------------------------------ writer --

class NbtWriter {
  NbtWriter({this.littleEndian = false});
  final bool littleEndian;
  final BytesBuilder _out = BytesBuilder(copy: false);

  void writeDoc(Map<String, Object?> root, {String name = ''}) {
    _u8(tagCompound);
    _string(name);
    _compound(root, 0);
  }

  Uint8List toBytes() => _out.toBytes();

  void _u8(int v) => _out.addByte(v & 0xFF);
  void _i8(int v) => _out.add(Int8List(1)..[0] = v);

  void _i16(int v) {
    final b = ByteData(2)..setInt16(0, v, littleEndian ? Endian.little : Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _i32(int v) {
    final b = ByteData(4)..setInt32(0, v, littleEndian ? Endian.little : Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _i64(int v) {
    final b = ByteData(8)..setInt64(0, v, littleEndian ? Endian.little : Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _f32(double v) {
    final b = ByteData(4)..setFloat32(0, v, littleEndian ? Endian.little : Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _string(String s) {
    final raw = utf8.encode(s);
    _u16(raw.length);
    _out.add(raw);
  }

  void _u16(int v) {
    final b = ByteData(2)..setUint16(0, v, littleEndian ? Endian.little : Endian.big);
    _out.add(b.buffer.asUint8List());
  }

  void _compound(Map<String, Object?> obj, int depth) {
    if (depth > 512) throw NbtException('too deep');
    obj.forEach((k, v) {
      final t = classify(v);
      if (t == null) return;
      _u8(t.$1);
      _string(k);
      _value(t.$1, t.$2, depth + 1);
    });
    _u8(tagEnd);
  }

  void _value(int tt, Object? v, int depth) {
    switch (tt) {
      case tagByte:
        _i8(v is bool ? (v ? 1 : 0) : (v as int));
        break;
      case tagShort:
        _i16(v as int);
        break;
      case tagInt:
        _i32(v as int);
        break;
      case tagLong:
        _i64(v as int);
        break;
      case tagFloat:
        _f32((v as num).toDouble());
        break;
      case tagDouble:
        {
          final b = ByteData(8)
            ..setFloat64(0, (v as num).toDouble(),
                littleEndian ? Endian.little : Endian.big);
          _out.add(b.buffer.asUint8List());
        }
        break;
      case tagString:
        _string(v as String);
        break;
      case tagByteArray:
        {
          final list = (v as Uint8List);
          _i32(list.length);
          _out.add(list);
        }
        break;
      case tagIntArray:
        {
          final list = (v as List<int>);
          _i32(list.length);
          for (final e in list) {
            _i32(e);
          }
        }
        break;
      case tagLongArray:
        {
          final list = (v as List<int>);
          _i32(list.length);
          for (final e in list) {
            _i64(e);
          }
        }
        break;
      case tagList:
        {
          final lt = v as NbtList;
          _u8(lt.itemType);
          _i32(lt.items.length);
          for (final item in lt.items) {
            if (lt.itemType == tagCompound) {
              _compound(Map<String, Object?>.from(item as Map), depth + 1);
            } else {
              final t = classify(item);
              _value(lt.itemType, t?.$2 ?? item, depth + 1);
            }
          }
        }
        break;
      case tagCompound:
        _compound(Map<String, Object?>.from(v as Map), depth);
        break;
      default:
        throw NbtException('cannot write tag $tt');
    }
  }

  static (int, Object?)? classify(Object? v) {
    if (v == null) return null;
    if (v is NbtByte) return (tagByte, v.value);
    if (v is NbtShort) return (tagShort, v.value);
    if (v is NbtInt) return (tagInt, v.value);
    if (v is NbtLong) return (tagLong, v.value);
    if (v is NbtFloat) return (tagFloat, v.value);
    if (v is bool) return (tagByte, v);
    if (v is int) return (tagLong, v);
    if (v is double) return (tagDouble, v);
    if (v is String) return (tagString, v);
    if (v is Uint8List) return (tagByteArray, v);
    if (v is NbtList) return (tagList, v);
    if (v is List<int>) return (tagIntArray, v);
    if (v is Map) return (tagCompound, v);
    throw NbtException('unsupported NBT value: ${v.runtimeType}');
  }
}

Uint8List writeNbtBytes(Map<String, Object?> root,
    {required bool littleEndian, bool gzipOutput = false, String name = ''}) {
  final w = NbtWriter(littleEndian: littleEndian);
  w.writeDoc(root, name: name);
  final bytes = w.toBytes();
  return gzipOutput ? Uint8List.fromList(gzip.encode(bytes)) : bytes;
}
