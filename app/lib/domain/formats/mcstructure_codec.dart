import 'dart:typed_data';

import '../model/design.dart';
import '../nbt/nbt.dart';
import '../validation/design_validator.dart';

/// Bedrock `.mcstructure` codec (little-endian NBT), mirroring
/// converter/src/.../parsers/mcstructure.py + exporters/mcstructure_out.py.
/// Layout per wiki.bedrock.dev/nbt/mcstructure (verified 2026-10-29).
class McstructureCodec {
  /// Palette state `version` written for every entry: the documented current
  /// value as of 1.26.30 (0x01153C21 → 18168865) so vanilla skips its
  /// legacy upgrade chain. Final validation remains in-game.
  static const blockVersion = 18168865;

  static ({Design? design, ValidationReport report}) parse(List<int> bytes,
      {String sourceName = 'structure'}) {
    final rep = ValidationReport();
    late NbtDoc doc;
    try {
      doc = readNbtBytes(bytes, littleEndian: true);
    } on NbtException catch (e) {
      rep.error('mcstructure.nbt', 'malformed mcstructure NBT: ${e.message}');
      return (design: null, report: rep);
    }
    final root = doc.root;

    final sizeList = root['size'];
    if (sizeList is! NbtList || sizeList.items.length != 3) {
      rep.error('mcstructure.size', 'missing or malformed size list');
      return (design: null, report: rep);
    }
    final size = sizeList.items
        .map((e) => e is NbtInt ? e.value : (e as num).toInt())
        .toList();
    final sx = size[0], sy = size[1], sz = size[2];
    if (sx < 1 || sy < 1 || sz < 1 || sx > 1024 || sy > 1024 || sz > 1024) {
      rep.error('mcstructure.size', 'structure size ${sx}x${sy}x${sz} out of range');
      return (design: null, report: rep);
    }

    final structure = root['structure'];
    if (structure is! Map) {
      rep.error('mcstructure.body', 'missing structure compound');
      return (design: null, report: rep);
    }
    final bi = structure['block_indices'];
    if (bi is! NbtList || bi.items.length != 2) {
      rep.error('mcstructure.indices', 'block_indices must contain two lists');
      return (design: null, report: rep);
    }
    final primary = (bi.items[0] as List).cast<Object?>();
    final secondary = (bi.items[1] as List).cast<Object?>();
    final n = sx * sy * sz;
    if (primary.length != n || secondary.length != n) {
      rep.error('mcstructure.indices',
          'block_indices length mismatch (${primary.length}/${secondary.length} vs $n)');
      return (design: null, report: rep);
    }

    final paletteRoot = structure['palette'];
    final def = paletteRoot is Map ? paletteRoot['default'] : null;
    final rawPalette = def is Map ? def['block_palette'] : null;
    if (rawPalette is! NbtList) {
      rep.error('mcstructure.palette', 'missing block_palette');
      return (design: null, report: rep);
    }

    final entries = <PaletteEntry>[];
    for (var i = 0; i < rawPalette.items.length; i++) {
      final e = rawPalette.items[i];
      if (e is! Map || e['name'] is! String) {
        rep.warning('mcstructure.palette', 'palette entry $i malformed; treated as air');
        entries.add(const PaletteEntry('minecraft:air'));
        continue;
      }
      var id = e['name'] as String;
      if (!id.contains(':')) id = 'minecraft:$id';
      final states = <String, Object>{};
      final st = e['states'];
      if (st is Map) {
        st.forEach((k, v) {
          if (k is! String) return;
          if (v is NbtByte) {
            states[k] = v.value != 0;
          } else if (v is NbtInt) {
            states[k] = v.value;
          } else if (v is NbtShort) {
            states[k] = v.value;
          } else if (v is int) {
            states[k] = v;
          } else if (v is String) {
            states[k] = v;
          }
        });
      }
      entries.add(PaletteEntry(id, states));
    }

    final blocks = <BlockEntry>[];
    for (var idx = 0; idx < n; idx++) {
      final pi = primary[idx];
      if (pi is! int || pi < 0 || pi >= entries.length) continue;
      final entry = entries[pi];
      if (entry.id == 'minecraft:air') continue;
      final z = idx % sz;
      final y = (idx ~/ sz) % sy;
      final x = idx ~/ (sz * sy);
      blocks.add(BlockEntry(x, y, z, pi));
      final si = secondary[idx];
      if (si is int && si >= 0 && si < entries.length) {
        rep.warning('mcstructure.colocated',
            'co-located block at ($x,$y,$z) ignored '
            '(${entries[si].id}); not representable in schematic3d-build v1');
      }
    }

    if (blocks.isEmpty) {
      rep.error('mcstructure.empty', 'structure contains no non-air blocks');
      return (design: null, report: rep);
    }

    final design = Design(
      name: sourceName,
      description: null,
      dimensions: (sx, sy, sz),
      palette: entries,
      blocks: blocks,
      layers: [Layer(id: 'all', yMin: 0, yMax: sy - 1, name: 'All layers')],
      metadata: const {'source': 'mcstructure', 'generator': 'schematic3d-app'},
    );
    return (design: design, report: rep);
  }

  /// Build the NBT compound for a .mcstructure file.
  static Map<String, Object?> buildRoot(Design design) {
    final sx = design.dimensions.$1;
    final sy = design.dimensions.$2;
    final sz = design.dimensions.$3;
    final n = sx * sy * sz;

    final paletteIndex = <String, int>{};
    final paletteList = <Map<String, Object?>>[];
    for (final pe in design.palette) {
      final key = _key(pe);
      if (!paletteIndex.containsKey(key)) {
        paletteIndex[key] = paletteList.length;
        final states = <String, Object?>{};
        for (final e in pe.states.entries) {
          final v = e.value;
          if (v is bool) {
            states[e.key] = NbtByte(v ? 1 : 0);
          } else if (v is int) {
            states[e.key] = NbtInt(v);
          } else {
            states[e.key] = v;
          }
        }
        paletteList.add({
          'name': pe.id,
          'states': states,
          'version': NbtInt(blockVersion),
        });
      }
    }

    final primary = List<int>.filled(n, -1);
    final secondary = List<int>.filled(n, -1);
    for (final b in design.blocks) {
      if (b.x < 0 || b.y < 0 || b.z < 0 || b.x >= sx || b.y >= sy || b.z >= sz) {
        continue;
      }
      final pe = design.palette[b.paletteIndex];
      final idx = paletteIndex[_key(pe)];
      if (idx == null) continue;
      primary[(b.x * sy + b.y) * sz + b.z] = idx;
    }

    return {
      'format_version': NbtInt(1),
      'size': NbtList(tagInt, [NbtInt(sx), NbtInt(sy), NbtInt(sz)]),
      'structure': {
        'block_indices': NbtList(tagIntArray, [primary, secondary]),
        'entities': NbtList(tagCompound, const []),
        'palette': {
          'default': {
            'block_palette': NbtList(tagCompound, paletteList),
            'block_position_data': <String, Object?>{},
          }
        },
      },
      'structure_world_origin':
          NbtList(tagInt, [const NbtInt(0), const NbtInt(0), const NbtInt(0)]),
    };
  }

  static Uint8List encode(Design design) =>
      writeNbtBytes(buildRoot(design), littleEndian: true);

  static String _key(PaletteEntry pe) {
    final parts = pe.states.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '${pe.id}{${parts.map((e) => '${e.key}=${e.value}').join(',')}}';
  }
}
