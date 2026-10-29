import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'mapper.dart';

/// Static Bedrock block-id snapshot + Java→Bedrock mapping tables.
/// Generated from the converter (`s3dc block-catalog`) so both stacks share
/// one source of truth; loaded from assets at startup.
class BlockCatalog implements BlockCatalogIface {
  BlockCatalog._({
    required this.known,
    required this.javaToBedrock,
    required this.javaFamily,
    required this.woodByLogValue,
  });

  final Set<String> known;

  /// java short name (no namespace) → bedrock full id
  @override
  final Map<String, String> javaToBedrock;

  /// family block (planks/log/leaves/wool/…) → variant → bedrock full id
  @override
  final Map<String, Map<String, String>> javaFamily;

  /// numeric wood_type for `log` family (java metadata era) fallback
  final Map<String, String> woodByLogValue;

  static BlockCatalog? _instance;
  static BlockCatalog get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('BlockCatalog.load() must run before use (see bootstrap)');
    }
    return i;
  }

  static Future<BlockCatalog> load({String asset = 'assets/generated/block_catalog.json'}) async {
    final raw = await rootBundle.loadString(asset);
    final doc = jsonDecode(raw) as Map<String, Object?>;
    final known = <String>{
      for (final id in (doc['knownBedrockIds'] as List? ?? const []))
        'minecraft:$id',
    };
    final j2b = <String, String>{
      for (final e in (doc['javaToBedrock'] as Map? ?? const {}).entries)
        if (e.key.toString() != "budding_copper?")
          e.key.toString(): e.value.toString(),
    };
    final fam = <String, Map<String, String>>{};
    for (final entry in (doc['javaFamilyToBedrock'] as Map? ?? const {}).entries) {
      final inner = entry.value;
      if (inner is Map) {
        fam[entry.key.toString()] = {
          for (final p in inner.entries) p.key.toString(): p.value.toString(),
        };
      }
    }
    final cat = BlockCatalog._(
      known: known,
      javaToBedrock: j2b,
      javaFamily: fam,
      woodByLogValue: const {
        '0': 'minecraft:oak_log', '1': 'minecraft:spruce_log',
        '2': 'minecraft:birch_log', '3': 'minecraft:jungle_log',
        '4': 'minecraft:acacia_log', '5': 'minecraft:dark_oak_log',
      },
    );
    _instance = cat;
    return cat;
  }

  /// For tests / non-asset load.
  static BlockCatalog adopt(BlockCatalog c) => _instance = c;

  /// Build + adopt a catalog from plain maps (used by VM tests without the
  /// asset bundle; production code goes through [load]).
  static BlockCatalog loadFromData({
    required Set<String> known,
    required Map<String, String> javaToBedrock,
    required Map<String, Map<String, String>> javaFamily,
  }) {
    final c = BlockCatalog._(
      known: known,
      javaToBedrock: javaToBedrock,
      javaFamily: javaFamily,
      woodByLogValue: const {},
    );
    _instance = c;
    return c;
  }

  String classify(String id) {
    if (!id.contains(':')) return 'invalid';
    if (id.startsWith('s3d:')) return 'known';
    if (known.contains(id)) return 'known';
    final ns = id.split(':').first;
    return ns == 'minecraft' ? 'unknown' : 'unknown';
  }
}
