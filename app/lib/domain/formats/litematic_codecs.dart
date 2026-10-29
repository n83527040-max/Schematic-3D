import 'dart:math' as math;

import '../model/design.dart';
import '../nbt/nbt.dart';
import '../validation/design_validator.dart';
import 'mapper.dart';

/// Sponge v2 `.schem` (WorldEdit 7) + Litematica `.schem` readers, matching
/// the Python implementations (converter/src/.../parsers/*).
class LitematicCodecs {
  LitematicCodecs(this.mapper);
  final Mapper mapper;

  /// Auto-detects which schem flavor the bytes contain.
  ({Design? design, ValidationReport report, ConversionResult conv, String fmt})
      parseSchem(List<int> bytes, {String sourceName = 'design'}) {
    late NbtDoc doc;
    final rep = ValidationReport();
    try {
      doc = readNbtBytes(bytes, littleEndian: false);
    } on NbtException catch (e) {
      rep.error('schem.nbt', 'malformed NBT: ${e.message}');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'unknown');
    }
    final body = doc.root['Schematic'] is Map
        ? doc.root['Schematic'] as Map
        : doc.root;
    if (body['Version'] == 2 && body['BlockData'] != null) {
      return _parseSponge2(Map<String, Object?>.from(body), rep,
          sourceName: sourceName);
    }
    final regions = body['Regions'];
    if (regions is Map) {
      return _parseLitematic(Map<String, Object?>.from(regions), rep,
          sourceName: sourceName);
    }
    rep.error('schem.format', 'neither Sponge-v2 nor Litematica layout found');
    return (design: null, report: rep, conv: ConversionResult(), fmt: 'unknown');
  }

  // ------------------------------------------------------------ sponge v2 --
  ({Design? design, ValidationReport report, ConversionResult conv, String fmt})
      _parseSponge2(Map<String, Object?> body, ValidationReport rep,
          {required String sourceName}) {
    int dim(String k) {
      final v = body[k];
      if (v is NbtInt) return v.value;
      if (v is int) return v;
      throw const FormatException('missing dimension');
    }

    late int w, h, l;
    try {
      w = dim('Width');
      h = dim('Height');
      l = dim('Length');
    } on FormatException catch (e) {
      rep.error('sponge2.dims', e.message.toString());
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'sponge2');
    }
    if (w < 1 || h < 1 || l < 1 || w > 512 || h > 512 || l > 512) {
      rep.error('sponge2.dims', 'dimensions $w x $h x $l outside 1..512');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'sponge2');
    }

    final palRaw = body['Palette'];
    final dataRaw = body['BlockData'];
    if (palRaw is! Map || dataRaw is! List<Object?>) {
      rep.error('sponge2.palette', 'missing Palette map or BlockData');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'sponge2');
    }

    final indexToState = <int, String>{};
    palRaw.forEach((k, v) {
      if (v is NbtInt) {
        indexToState[v.value] = k.toString();
      } else if (v is int) {
        indexToState[v] = k.toString();
      }
    });

    final n = w * h * l;
    final order = _readVarints(dataRaw, n, rep);
    if (order == null) {
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'sponge2');
    }

    final conv = ConversionResult();
    final bedrockPalette = <PaletteEntry>[];
    final stateToMerged = <String, int?>{};
    final airByIndex = <int>{};
    for (final idx in indexToState.keys.toList()..sort()) {
      final stateKey = indexToState[idx]!;
      final java = splitBlockState(stateKey);
      if (java.id.endsWith(':air')) {
        airByIndex.add(idx);
        stateToMerged[stateKey] = null;
        conv.add(stateKey, 'air', null, const []);
        continue;
      }
      final res = mapper.mapJavaEntry(java);
      final action = switch (res.action) {
        MapAction.pass => 'pass',
        MapAction.renamed => 'renamed',
        MapAction.family => 'family',
        MapAction.stateChanged => 'state-changed',
        MapAction.unsupported => 'unsupported',
      };
      if (res.action == MapAction.unsupported) {
        stateToMerged[stateKey] = null;
        conv.add(stateKey, action, null, res.notes);
        continue;
      }
      final merged = bedrockPalette.firstWhere(
        (e) => _samePerm(e, res.entry),
        orElse: () {
          bedrockPalette.add(res.entry);
          return res.entry;
        },
      );
      stateToMerged[stateKey] = bedrockPalette.indexOf(merged);
      conv.add(stateKey, action, res.entry.commandToken, res.notes);
    }

    final blocks = <BlockEntry>[];
    var dropped = 0;
    for (var i = 0; i < n; i++) {
      final idx = order[i];
      final stateKey = indexToState[idx];
      if (stateKey == null) {
        dropped++;
        continue;
      }
      if (airByIndex.contains(idx)) continue;
      final mapped = stateToMerged[stateKey];
      if (mapped == null) {
        dropped++;
        continue;
      }
      final x = i % w;
      final z = (i ~/ w) % l;
      final y = i ~/ (w * l);
      blocks.add(BlockEntry(x, y, z, mapped));
    }

    if (blocks.isEmpty) {
      rep.error('sponge2.empty', 'no blocks left after mapping');
      return (design: null, report: rep, conv: conv, fmt: 'sponge2');
    }
    conv.droppedBlocks = dropped;
    if (dropped > 0) {
      rep.warning('sponge2.dropped',
          '$dropped block(s) had no Bedrock mapping and were dropped');
    }

    Map<String, Object?>? meta;
    if (body['Metadata'] is Map) meta = Map<String, Object?>.from(body['Metadata'] as Map);
    final name = meta?['Name'] is String ? meta!['Name'] as String : sourceName;

    final design = Design(
      name: name.length > 200 ? name.substring(0, 200) : name,
      description: 'Imported from Sponge v2 .schem',
      dimensions: (w, h, l),
      palette: bedrockPalette,
      blocks: blocks,
      layers: [Layer(id: 'all', yMin: 0, yMax: h - 1, name: 'All layers')],
      metadata: {
        'source': 'sponge2',
        'generator': 'schematic3d-app',
        if (meta != null) 'originalName': meta['Name'],
        if (dropped > 0) 'unsupportedFeatures': conv.unsupportedBlocks,
      },
    );
    return (design: design, report: rep, conv: conv, fmt: 'sponge2');
  }

  List<int>? _readVarints(List<Object?> raw, int count, ValidationReport rep) {
    final data = raw;
    final out = <int>[];
    var i = 0;
    while (out.length < count) {
      if (i >= data.length) {
        rep.error('sponge2.varints', 'truncated varint stream');
        return null;
      }
      var shift = 0;
      var val = 0;
      while (true) {
        if (i >= data.length) {
          rep.error('sponge2.varints', 'truncated varint');
          return null;
        }
        final byte = (data[i] is NbtByte ? (data[i] as NbtByte).value : (data[i] as int)) & 0xFF;
        i++;
        val |= (byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
        if (shift > 28) {
          rep.error('sponge2.varints', 'varint too large');
          return null;
        }
      }
      out.add(val);
    }
    return out;
  }

  // ----------------------------------------------------------- litematic --
  ({Design? design, ValidationReport report, ConversionResult conv, String fmt})
      _parseLitematic(Map<String, Object?> regions, ValidationReport rep,
          {required String sourceName}) {
    final name = regions.keys.first;
    final regionRaw = regions[name];
    if (regionRaw is! Map) {
      rep.error('litematic.region', 'region "$name" malformed');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'litematic');
    }
    final region = Map<String, Object?>.from(regionRaw);

    List<int>? intList(Object? v) {
      if (v is NbtList) return v.items.map((e) => (e as num).toInt()).toList();
      if (v is List) return v.map((e) => (e as num).toInt()).toList();
      return null;
    }

    final size = intList(region['Size']);
    if (size == null || size.length != 3) {
      rep.error('litematic.size', 'missing Size');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'litematic');
    }
    final sx = size[0].abs(), sy = size[1].abs(), sz = size[2].abs();
    if (sx < 1 || sy < 1 || sz < 1 || sx > 512 || sy > 512 || sz > 512) {
      rep.error('litematic.size', 'size $sx x $sy x $sz outside 1..512');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'litematic');
    }

    final paletteList = region['Palette'];
    if (paletteList is! NbtList || paletteList.items.isEmpty) {
      rep.error('litematic.palette', 'missing Palette');
      return (design: null, report: rep, conv: ConversionResult(), fmt: 'litematic');
    }

    final conv = ConversionResult();
    final bedrockPalette = <PaletteEntry>[];
    final paletteMap = <int, int?>{};
    var airIndex = -1;
    for (var i = 0; i < paletteList.items.length; i++) {
      final e = paletteList.items[i];
      if (e is! Map || e['Name'] is! String) {
        conv.add('malformed#$i', 'unsupported', null, const []);
        paletteMap[i] = null;
        continue;
      }
      final jname = e['Name'] as String;
      if (jname.endsWith(':air')) airIndex = i;
      var id = jname;
      if (!id.contains(':')) id = 'minecraft:$id';
      if (id.startsWith('bedrock:')) {
        id = 'minecraft:${id.substring('bedrock:'.length)}';
      }
      final statesRaw = e['Properties'];
      final states = <String, Object>{};
      if (statesRaw is Map) {
        statesRaw.forEach((k, v) {
          if (v is String) {
            final low = v.toLowerCase();
            if (low == 'true' || low == 'false') {
              states[k.toString()] = low == 'true';
            } else {
              final asInt = int.tryParse(v);
              states[k.toString()] = asInt ?? v;
            }
          } else if (v is num) {
            states[k.toString()] = v.toInt();
          }
        });
      }
      final res = mapper.mapJavaEntry(PaletteEntry(id, states));
      final javaLabel = states.isEmpty
          ? id
          : '$id[${states.entries.map((x) => '${x.key}=${x.value}').join(',')}]';
      final action = switch (res.action) {
        MapAction.pass => 'pass',
        MapAction.renamed => 'renamed',
        MapAction.family => 'family',
        MapAction.stateChanged => 'state-changed',
        MapAction.unsupported => 'unsupported',
      };
      if (res.action == MapAction.unsupported) {
        paletteMap[i] = null;
        conv.add(javaLabel, action, null, res.notes);
        continue;
      }
      var idx = -1;
      for (var k = 0; k < bedrockPalette.length; k++) {
        if (_samePerm(bedrockPalette[k], res.entry)) {
          idx = k;
          break;
        }
      }
      if (idx < 0) {
        bedrockPalette.add(res.entry);
        idx = bedrockPalette.length - 1;
      }
      paletteMap[i] = idx;
      conv.add(javaLabel, action, res.entry.commandToken, res.notes);
    }

    final longsRaw = region['BlockStates'];
    if (longsRaw is! NbtList && longsRaw is! List<Object?>) {
      rep.error('litematic.states', 'missing BlockStates');
      return (design: null, report: rep, conv: conv, fmt: 'litematic');
    }
    final longs = (longsRaw is NbtList
            ? longsRaw.items
            : longsRaw as List<Object?>).map((e) {
          final v = e is NbtLong ? e.value : (e as num).toInt();
          return v.toUnsigned(64);
        })
        .toList(growable: false);

    final n = sx * sy * sz;
    final bits = _bitsFor(paletteList.items.length);
    final perLong = 64 ~/ bits;
    final mask = (1 << bits) - 1;

    final blocks = <BlockEntry>[];
    var dropped = 0;
    var idx = 0;
    for (var li = 0; li < longs.length && idx < n; li++) {
      final word = longs[li];
      final entriesThis = math.min(n - idx, perLong);
      for (var e = 0; e < entriesThis; e++) {
        final val = (word >> (e * bits)) & mask;
        final x = idx ~/ (sy * sz);
        final rem = idx % (sy * sz);
        final y = rem ~/ sz;
        final z = rem % sz;
        idx++;
        if (val == airIndex) continue;
        final mapped = paletteMap[val];
        if (mapped == null) {
          dropped++;
          continue;
        }
        blocks.add(BlockEntry(x, y, z, mapped));
      }
    }

    if (blocks.isEmpty) {
      rep.error('litematic.empty', 'no blocks after mapping');
      return (design: null, report: rep, conv: conv, fmt: 'litematic');
    }
    conv.droppedBlocks = dropped;
    if (dropped > 0) {
      rep.warning('litematic.dropped',
          '$dropped block(s) have no Bedrock equivalent and were removed');
    }
    final design = Design(
      name: sourceName,
      description: 'Imported from Litematica region "$name"',
      dimensions: (sx, sy, sz),
      palette: bedrockPalette,
      blocks: blocks,
      layers: [Layer(id: 'all', yMin: 0, yMax: sy - 1, name: 'All layers')],
      metadata: {
        'source': 'litematic',
        'generator': 'schematic3d-app',
        if (dropped > 0) 'unsupportedFeatures': conv.unsupportedBlocks,
      },
    );
    return (design: design, report: rep, conv: conv, fmt: 'litematic');
  }

  static int _bitsFor(int paletteSize) {
    var bits = 0;
    var v = paletteSize - 1;
    while (v > 0) {
      bits++;
      v >>= 1;
    }
    return math.max(2, bits);
  }

  static bool _samePerm(PaletteEntry a, PaletteEntry b) {
    if (a.id != b.id) return false;
    if (a.states.length != b.states.length) return false;
    for (final e in a.states.entries) {
      if (b.states[e.key]?.toString() != e.value.toString()) return false;
    }
    return true;
  }

  /// `minecraft:name[a=1,b=true]` → PaletteEntry.
  static PaletteEntry splitBlockState(String key) {
    final k = key.trim();
    var base = k;
    final states = <String, Object>{};
    final bracket = k.indexOf('[');
    if (bracket >= 0 && k.endsWith(']')) {
      base = k.substring(0, bracket);
      final inner = k.substring(bracket + 1, k.length - 1);
      for (final part in _splitTopLevel(inner)) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        final sk = part.substring(0, eq).trim();
        final sv = part.substring(eq + 1).trim();
        Object val;
        if (sv == 'true' || sv == 'false') {
          val = sv == 'true';
        } else {
          val = int.tryParse(sv) ?? sv;
        }
        if (Limits.stateKeyRe.hasMatch(sk)) states[sk] = val;
      }
    }
    if (!base.contains(':')) base = 'minecraft:$base';
    if (base.startsWith('bedrock:')) {
      base = 'minecraft:${base.substring('bedrock:'.length)}';
    }
    return PaletteEntry(base, states);
  }

  static List<String> _splitTopLevel(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final ch in s.split('')) {
      if (ch == '[') depth++;
      if (ch == ']') depth--;
      if (ch == ',' && depth == 0) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }
}

class ConversionResult {
  final List<Map<String, Object?>> entries = [];
  int droppedBlocks = 0;

  List<String> get unsupportedBlocks => entries
      .where((e) => e['action'] == 'unsupported')
      .map((e) => e['java'].toString())
      .toList(growable: false);

  void add(String java, String action, String? bedrock, List<String> notes) {
    entries.add({
      'java': java,
      'action': action,
      'bedrock': bedrock,
      if (notes.isNotEmpty) 'notes': notes,
    });
  }

  Map<String, Object?> toJson() =>
      {'entries': entries, 'droppedBlocks': droppedBlocks};
}
