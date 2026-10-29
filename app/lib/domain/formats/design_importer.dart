import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/design.dart';
import '../validation/design_validator.dart';
import 'block_catalog.dart';
import 'litematic_codecs.dart';
import 'mapper.dart';
import 'mcstructure_codec.dart';

enum DesignFormat { schematic3dJson, mcstructure, schem, schematic, unknown }

class ImportOutcome {
  ImportOutcome({
    required this.format,
    this.design,
    required this.report,
    this.conversion,
  });

  final DesignFormat format;
  final Design? design;
  final ValidationReport report;
  final ConversionResult? conversion;

  bool get ok => report.ok && design != null;
}

/// Entry point for "import a file": sniffs content (not extension), parses
/// with the right codec, validates. The ORIGINAL bytes are always kept by
/// the repository layer before this runs (acceptance criterion).
class DesignImporter {
  DesignImporter({Mapper? mapper})
      : mapper = mapper ?? Mapper(BlockCatalog.instance);

  final Mapper mapper;

  Future<ImportOutcome> importFile(File file) =>
      importBytes(file.readAsBytesSync(), fileName: file.path.split('/').last);

  ImportOutcome importBytes(Uint8List bytes, {String fileName = 'design'}) {
    final name = fileName.split('/').last.replaceAll(RegExp(r'\.(json|mcstructure|schem|schematic)$', caseSensitive: false), '');
    final fmt = sniff(bytes, fileName);
    switch (fmt) {
      case DesignFormat.schematic3dJson:
        return _fromJson(bytes, name);
      case DesignFormat.mcstructure:
        final r = McstructureCodec.parse(bytes, sourceName: name);
        return ImportOutcome(
            format: fmt, design: r.design, report: r.report);
      case DesignFormat.schem:
        final r = LitematicCodecs(mapper).parseSchem(bytes, sourceName: name);
        return ImportOutcome(
            format: fmt,
            design: r.design,
            report: r.report,
            conversion: r.conv);
      case DesignFormat.schematic:
        final r = parseLegacySchematic(bytes, report: _rep());
        return ImportOutcome(
            format: fmt, design: r.design, report: r.report);
      case DesignFormat.unknown:
        final rep = ValidationReport()
          ..error('format.unknown',
              'unrecognized file — supported: .json (schematic3d-build), '
              '.mcstructure, .schem (Sponge v2 / Litematica), .schematic');
        return ImportOutcome(format: fmt, report: rep);
    }
  }

  ValidationReport _rep() => ValidationReport();

  ImportOutcome _fromJson(Uint8List bytes, String name) {
    final rep = ValidationReport();
    Object? doc;
    try {
      doc = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } catch (e) {
      rep.error('json.parse', 'invalid JSON: $e');
      return ImportOutcome(format: DesignFormat.schematic3dJson, report: rep);
    }
    if (doc is! Map<String, Object?>) {
      rep.error('json.root', 'top level JSON must be an object');
      return ImportOutcome(format: DesignFormat.schematic3dJson, report: rep);
    }
    if (doc['format'] != Design.kSchematicFormat) {
      rep.error('format',
          'this JSON is not a "${Design.kSchematicFormat}" document; images and '
          'other AI outputs are not build data', '\$.format');
      return ImportOutcome(format: DesignFormat.schematic3dJson, report: rep);
    }
    final v = validateSchematicDoc(doc,
        classifyId: (id) => BlockCatalog.instance.classify(id));
    return ImportOutcome(
        format: DesignFormat.schematic3dJson,
        design: v.design,
        report: v.report);
  }

  static DesignFormat sniff(List<int> bytes, String fileName) {
    var data = bytes;
    if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
      try {
        data = Uint8List.fromList(gzip.decode(data));
      } catch (_) {/* keep raw */}
    }
    var s = data;
    // skip BOM/whitespace for JSON check
    var start = 0;
    while (start < s.length &&
        (s[start] == 0x20 || s[start] == 0x0a || s[start] == 0x0d ||
            s[start] == 0x09 ||
            (start + 2 < s.length && s[start] == 0xEF && s[start + 1] == 0xBB && s[start + 2] == 0xBF))) {
      start++;
    }
    s = s.sublist(start);
    if (s.isNotEmpty && s[0] == 0x7B) return DesignFormat.schematic3dJson;
    if (s.length > 4 && s[0] == 0x0A) {
      // NBT compound — try little-endian mcstructure marker
      final little = _looksLikeMcstructure(s, littleEndian: true);
      if (little) return DesignFormat.mcstructure;
      final ext = fileName.toLowerCase();
      if (ext.endsWith('.mcstructure')) return DesignFormat.mcstructure;
      if (ext.endsWith('.schem')) return DesignFormat.schem;
      if (ext.endsWith('.schematic')) return DesignFormat.schematic;
      // heuristic on root keys via big-endian compound names
      final rootName = _rootName(s, false);
      if (rootName == 'Schematic') {
        return _hasVersion2(s) ? DesignFormat.schem : DesignFormat.schematic;
      }
      if (rootName == 'Litematic' || rootName == 'schematic') {
        return DesignFormat.schem;
      }
      return DesignFormat.schem;
    }
    return DesignFormat.unknown;
  }

  static bool _looksLikeMcstructure(List<int> b, {required bool littleEndian}) {
    try {
      final doc = readNbtBytes(b, littleEndian: littleEndian);
      return doc.root.containsKey('format_version') &&
          doc.root.containsKey('structure');
    } catch (_) {
      return false;
    }
  }

  static String? _rootName(List<int> b, bool littleEndian) {
    try {
      // root type byte + name length + name
      if (b.length < 3) return null;
      final len = littleEndian
          ? b[1] | (b[2] << 8)
          : (b[1] << 8) | b[2];
      if (b.length < 3 + len) return null;
      return utf8.decode(b.sublist(3, 3 + len));
    } catch (_) {
      return null;
    }
  }

  static bool _hasVersion2(List<int> b) {
    try {
      final doc = readNbtBytes(b, littleEndian: false);
      final body = doc.root['Schematic'] is Map
          ? doc.root['Schematic'] as Map
          : doc.root;
      final v = body['Version'];
      final vv = v is NbtInt ? v.value : v;
      return vv == 2 && body['BlockData'] != null;
    } catch (_) {
      return false;
    }
  }
}

// Legacy MCEdit `.schematic` minimal support: kept close to the Python
// implementation; curated id table subset + explicit unmapped reporting.
({Design? design, ValidationReport report}) parseLegacySchematic(
    List<int> bytes, {required ValidationReport report}) {
  late NbtDoc doc;
  try {
    doc = readNbtBytes(bytes, littleEndian: false);
  } catch (e) {
    report.error('schematic.nbt', 'malformed schematic NBT: $e');
    return (design: null, report: report);
  }
  final root = doc.root;
  int n(String k) {
    final v = root[k];
    if (v is NbtShort) return v.value;
    if (v is NbtInt) return v.value;
    if (v is int) return v;
    throw const FormatException('missing $k');
  }

  late int w, h, l;
  try {
    w = n('Width');
    h = n('Height');
    l = n('Length');
  } on FormatException catch (e) {
    report.error('schematic.dims', e.message.toString());
    return (design: null, report: report);
  }
  if (w < 1 || h < 1 || l < 1 || w > 512 || h > 512 || l > 512) {
    report.error('schematic.dims', 'dimensions $w x $h x $l outside 1..512');
    return (design: null, report: report);
  }
  final blocksRaw = root['Blocks'];
  if (blocksRaw is! Uint8List || blocksRaw.length != w * h * l) {
    report.error('schematic.blocks', 'Blocks array missing or wrong length');
    return (design: null, report: report);
  }
  final materials = root['Materials'];
  final mats = <String?>[];
  if (materials is NbtList && materials.itemType == tagString) {
    for (final m in materials.items) {
      var s = m.toString();
      if (s.startsWith('old:')) s = s.substring(4);
      mats.add(s);
    }
  }

  final palette = <PaletteEntry>[];
  final paletteIdx = <String, int>{};
  final out = <BlockEntry>[];
  final unmapped = <String, int>{};
  final nCells = w * h * l;
  for (var i = 0; i < nCells; i++) {
    final id = blocksRaw[i];
    if (id == 0) continue;
    String? name;
    if (mats.isNotEmpty && id < mats.length) name = mats[id];
    if (name == null || name.toLowerCase() == 'air') continue;
    final bedrock = _legacyNameMap[name.toLowerCase()];
    if (bedrock == null) {
      unmapped[name] = (unmapped[name] ?? 0) + 1;
      continue;
    }
    final pe = PaletteEntry(bedrock);
    final key = bedrock;
    final pi = paletteIdx.putIfAbsent(key, () {
      palette.add(pe);
      return palette.length - 1;
    });
    // index = (y * Length + z) * Width + x
    final x = i % w;
    final z = (i ~/ w) % l;
    final y = i ~/ (w * l);
    out.add(BlockEntry(x, y, z, pi));
  }
  for (final e in unmapped.entries.take(32)) {
    report.warning('schematic.unsupported',
        'legacy block "${e.key}" ×${e.value} has no Bedrock mapping; dropped');
  }
  if (out.isEmpty) {
    report.error('schematic.empty',
        'no blocks left after mapping (this file may need a fuller '
        'Java legacy id table — see converter docs)');
    return (design: null, report: report);
  }
  final design = Design(
    name: 'schematic import',
    dimensions: (w, h, l),
    palette: palette,
    blocks: out,
    layers: [Layer(id: 'all', yMin: 0, yMax: h - 1, name: 'All layers')],
    metadata: const {'source': 'schematic', 'generator': 'schematic3d-app'},
  );
  return (design: design, report: report);
}

const _legacyNameMap = <String, String>{
  'stone': 'minecraft:stone',
  'grass': 'minecraft:grass',
  'dirt': 'minecraft:dirt',
  'cobblestone': 'minecraft:cobblestone',
  'planks': 'minecraft:oak_planks',
  'bedrock': 'minecraft:bedrock',
  'water': 'minecraft:water',
  'flowing_water': 'minecraft:water',
  'lava': 'minecraft:lava',
  'flowing_lava': 'minecraft:lava',
  'sand': 'minecraft:sand',
  'gravel': 'minecraft:gravel',
  'gold_ore': 'minecraft:gold_ore',
  'iron_ore': 'minecraft:iron_ore',
  'coal_ore': 'minecraft:coal_ore',
  'log': 'minecraft:oak_log',
  'leaves': 'minecraft:oak_leaves',
  'sponge': 'minecraft:sponge',
  'glass': 'minecraft:glass',
  'lapis_ore': 'minecraft:lapis_ore',
  'lapis_block': 'minecraft:lapis_block',
  'sandstone': 'minecraft:sandstone',
  'noteblock': 'minecraft:noteblock',
  'white_wool': 'minecraft:white_wool',
  'brick_block': 'minecraft:bricks',
  'tnt': 'minecraft:tnt',
  'bookshelf': 'minecraft:bookshelf',
  'mossy_cobblestone': 'minecraft:mossy_cobblestone',
  'obsidian': 'minecraft:obsidian',
  'torch': 'minecraft:torch',
  'oak_stairs': 'minecraft:oak_stairs',
  'chest': 'minecraft:chest',
  'diamond_ore': 'minecraft:diamond_ore',
  'diamond_block': 'minecraft:diamond_block',
  'crafting_table': 'minecraft:crafting_table',
  'farmland': 'minecraft:farmland',
  'fence': 'minecraft:oak_fence',
  'glowstone': 'minecraft:glowstone',
  'ice': 'minecraft:ice',
  'snow': 'minecraft:snow',
  'snow_layer': 'minecraft:snow_layer',
  'cactus': 'minecraft:cactus',
  'clay': 'minecraft:clay',
  'jukebox': 'minecraft:jukebox',
  'netherrack': 'minecraft:netherrack',
  'soul_sand': 'minecraft:soul_sand',
  'melon_block': 'minecraft:melon_block',
  'brick_stairs': 'minecraft:brick_stairs',
  'stone_brick_stairs': 'minecraft:stone_brick_stairs',
  'nether_brick': 'minecraft:nether_brick',
  'nether_brick_stairs': 'minecraft:nether_brick_stairs',
  'end_stone': 'minecraft:end_stone',
  'redstone_lamp': 'minecraft:redstone_lamp',
  'emerald_ore': 'minecraft:emerald_ore',
  'emerald_block': 'minecraft:emerald_block',
  'gold_block': 'minecraft:gold_block',
  'iron_block': 'minecraft:iron_block',
  'quartz_block': 'minecraft:quartz_block',
  'quartz_stairs': 'minecraft:quartz_stairs',
  'hay_block': 'minecraft:hay_block',
  'hardened_clay': 'minecraft:terracotta',
  'coal_block': 'minecraft:coal_block',
  'packed_ice': 'minecraft:packed_ice',
  'iron_bars': 'minecraft:iron_bars',
  'redstone_block': 'minecraft:redstone_block',
  'hopper': 'minecraft:hopper',
  'ladder': 'minecraft:ladder',
  'stonebrick': 'minecraft:stone_bricks',
  'cobblestone_wall': 'minecraft:cobblestone_wall',
  'stone_stairs': 'minecraft:stone_stairs',
};
