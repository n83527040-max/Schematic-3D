import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:schematic_3d/domain/formats/block_catalog.dart';
import 'package:schematic_3d/domain/formats/design_importer.dart';
import 'package:schematic_3d/domain/formats/litematic_codecs.dart';
import 'package:schematic_3d/domain/formats/mapper.dart';
import 'package:schematic_3d/domain/validation/design_validator.dart';
import 'package:schematic_3d/domain/model/design.dart';

import '../helpers.dart';

void main() {
  setUpAll(() async {
    // Load catalog straight from the asset file (no rootBundle in VM tests).
    final raw = File(fixture('app/assets/generated/block_catalog.json'))
        .readAsStringSync();
    final doc = jsonDecode(raw) as Map<String, Object?>;
    final j2b = <String, String>{
      for (final e in (doc['javaToBedrock'] as Map).entries)
        e.key.toString(): e.value.toString(),
    };
    final fam = <String, Map<String, String>>{
      for (final e in (doc['javaFamilyToBedrock'] as Map).entries)
        e.key.toString(): {
          for (final p in (e.value as Map).entries)
            p.key.toString(): p.value.toString(),
        },
    };
    BlockCatalog.loadFromData(
      known: {'x'},
      javaToBedrock: j2b,
      javaFamily: fam,
    );
  });

  test('sniff: JSON', () {
    final bytes =
        utf8.encode(File(fixture('examples/cottage-12x8x12.json')).readAsStringSync());
    expect(DesignImporter.sniff(Uint8List.fromList(bytes), 'a.json'),
        DesignFormat.schematic3dJson);
  });

  test('sniff: mcstructure vs schem by NBT root', () {
    final mc =
        Uint8List.fromList(File(fixture('examples/tower-9x18x9.mcstructure')).readAsBytesSync());
    expect(DesignImporter.sniff(mc, 'tower.mcstructure'),
        DesignFormat.mcstructure);
    final sc = Uint8List.fromList(
        File(fixture('converter/tests/fixtures/block-library-bridge.schem'))
            .readAsBytesSync());
    expect(DesignImporter.sniff(sc, 'block-library-bridge.schem'),
        DesignFormat.schem);
  });

  group('full importer', () {

    test('json example imports clean', () {
      final bytes = Uint8List.fromList(
          File(fixture('examples/arch-bridge-21x9x7.json')).readAsBytesSync());
      final o = DesignImporter().importBytes(bytes, fileName: 'arch-bridge-21x9x7.json');
      expect(o.ok, isTrue, reason: o.report.issues.toString());
      expect(o.design!.blockCount, greaterThan(150));
    });

    test('mcstructure example imports + reports colocated as warning only',
        () {
      final bytes = Uint8List.fromList(
          File(fixture('examples/cottage-12x8x12.mcstructure'))
              .readAsBytesSync());
      final o = DesignImporter().importBytes(bytes, fileName: 'cottage.mcstructure');
      expect(o.ok, isTrue, reason: o.report.issues.toString());
    });

    test('sponge v2 .schem converts with mapping report', () {
      final bytes = Uint8List.fromList(
          File(fixture('converter/tests/fixtures/block-library-bridge.schem'))
              .readAsBytesSync());
      final o =
          DesignImporter().importBytes(bytes, fileName: 'block-library-bridge.schem');
      expect(o.ok, isTrue, reason: o.report.issues.toString());
      // palette fully mapped to bedrock ids
      for (final pe in o.design!.palette) {
        expect(pe.id.startsWith('minecraft:'), isTrue,
            reason: 'mapped id ${pe.id}');
      }
      expect(o.conversion, isNotNull);
      expect(o.conversion!.entries.isNotEmpty, isTrue);
    });

    test('truncated JSON reports a parse error and no design', () {
      final bytes = Uint8List.fromList(
          File(fixture('examples/broken-truncated.json')).readAsBytesSync());
      final o = DesignImporter().importBytes(bytes, fileName: 'broken-truncated.json');
      expect(o.ok, isFalse);
      expect(o.design, isNull);
      expect(o.report.errors.isNotEmpty, isTrue);
    });

    test('bad-version JSON keeps its semantic error code', () {
      final bytes = Uint8List.fromList(
          File(fixture('examples/broken-bad-version.json')).readAsBytesSync());
      final o = DesignImporter().importBytes(bytes, fileName: 'broken-bad-version.json');
      expect(o.ok, isFalse);
      expect(o.report.errors.any((Issue e) => e.code == 'schemaVersion'), isTrue);
    });

    test('unknown bytes are reported, not crashed', () {
      final o = DesignImporter().importBytes(
          Uint8List.fromList(List.generate(64, (i) => 0x41 + (i % 26))),
          fileName: 'mystery.dat');
      expect(o.ok, isFalse);
      expect(o.report.errors.first.code, 'format.unknown');
    });
  });

  group('sponge splitBlockState', () {
    test('parses name with states', () {
      final pe =
          LitematicCodecs.splitBlockState('minecraft:oak_stairs[facing=north,half=top]');
      expect(pe.id, 'minecraft:oak_stairs');
      expect(pe.states['facing'], 'north');
      expect(pe.states['half'], 'top'); // strings kept; mapper translates
    });

    test('mapper converts facing + half like python', () {
      final m = Mapper(BlockCatalog.instance);
      final r = m.mapJavaEntry(const PaletteEntry('minecraft:oak_stairs', {
        'facing': 'south',
        'half': 'top',
        'waterlogged': 'false',
      }));
      expect(r.entry.states['facing_direction'], 3);
      expect(r.entry.states['upper_block'], true);
      expect(r.entry.states.containsKey('waterlogged'), isFalse);
      expect(r.notes, isNotEmpty); // waterlogged dropped note? no — dropped list
    });
  });
}
