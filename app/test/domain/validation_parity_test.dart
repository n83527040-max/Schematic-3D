import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schematic_3d/domain/model/design.dart';
import 'package:schematic_3d/domain/validation/design_validator.dart';

import '../helpers.dart';

/// Golden parity with converter/tests/test_json_validation.py — same inputs,
/// same issue codes. If a case diverges, the shared fixtures here catch it.
Map<String, Object?> baseDoc() => {
      'format': 'schematic3d-build',
      'schemaVersion': 1,
      'name': 'Test House',
      'targetEdition': 'bedrock',
      'dimensions': {'x': 2, 'y': 1, 'z': 2},
      'palette': [
        {'id': 'minecraft:stone', 'states': <String, Object>{}},
      ],
      'blocks': [
        {'x': 0, 'y': 0, 'z': 0, 'paletteIndex': 0},
        {'x': 1, 'y': 0, 'z': 0, 'paletteIndex': 0},
        {'x': 0, 'y': 0, 'z': 1, 'paletteIndex': 0},
      ],
    };

void main() {
  test('minimal valid doc builds a Design', () {
    final r = validateSchematicDoc(baseDoc());
    expect(r.report.ok, isTrue, reason: r.report.issues.toString());
    expect(r.design!.blocks.length, 3);
    expect(r.design!.dimensions, (2, 1, 2));
  });

  test('bad schemaVersion rejected (same code as python)', () {
    final d = Map<String, Object?>.from(baseDoc())..['schemaVersion'] = 2;
    final r = validateSchematicDoc(d);
    expect(r.report.errors.any((e) => e.code == 'schemaVersion'), isTrue);
  });

  test('bad format rejected', () {
    final d = Map<String, Object?>.from(baseDoc())..['format'] = 'other';
    final r = validateSchematicDoc(d);
    expect(r.report.errors.any((e) => e.code == 'format'), isTrue);
  });

  test('out-of-bounds coordinate rejected', () {
    final d = Map<String, Object?>.from(baseDoc());
    d['blocks'] = [
      ...(d['blocks'] as List),
      {'x': 7, 'y': 0, 'z': 0, 'paletteIndex': 0},
    ];
    final r = validateSchematicDoc(d);
    expect(r.report.errors.any((e) => e.code == 'blocks.bounds'), isTrue);
  });

  test('bad paletteIndex rejected', () {
    final d = Map<String, Object?>.from(baseDoc());
    d['blocks'] = [
      {'x': 0, 'y': 0, 'z': 0, 'paletteIndex': 42},
      ...(d['blocks'] as List).sublist(1),
    ];
    final r = validateSchematicDoc(d);
    expect(r.report.errors.any((e) => e.code == 'blocks.paletteIndex'),
        isTrue);
  });

  test('duplicate coordinate rejected', () {
    final d = Map<String, Object?>.from(baseDoc());
    d['blocks'] = [
      ...(d['blocks'] as List),
      {'x': 0, 'y': 0, 'z': 0, 'paletteIndex': 0},
    ];
    final r = validateSchematicDoc(d);
    expect(r.report.errors.any((e) => e.code == 'blocks.duplicate'), isTrue);
  });

  test('duplicate palette entries merged', () {
    final d = Map<String, Object?>.from(baseDoc());
    d['palette'] = [
      ...(d['palette'] as List),
      {'id': 'minecraft:stone', 'states': <String, Object>{}},
    ];
    final r = validateSchematicDoc(d);
    expect(r.report.ok, isTrue);
    expect(r.design!.palette.length, 1);
    expect(r.design!.blocks.map((b) => b.paletteIndex).toSet(), {0});
  });

  test('broken fixtures produce matching error codes', () {
    final expectations = <String, String>{
      'broken-bad-version.json': 'schemaVersion',
      'broken-out-of-bounds.json': 'blocks.bounds',
      'broken-bad-palette-index.json': 'blocks.paletteIndex',
      'broken-duplicate.json': 'blocks.duplicate',
    };
    for (final e in expectations.entries) {
      final path = fixture('examples/${e.key}');
      final doc = readJsonFixture('examples/${e.key}');
      expect(File(path).existsSync(), isTrue, reason: path);
      final r = validateSchematicDoc(doc);
      expect(r.report.ok, isFalse, reason: e.key);
      expect(
        r.report.errors.any((i) => i.code == e.value),
        isTrue,
        reason: '${e.key}: expected ${e.value} in '
            '${r.report.errors.map((x) => x.code).toList()}',
      );
    }
  });

  test('truncated fixture fails to parse as JSON', () {
    final raw =
        File(fixture('examples/broken-truncated.json')).readAsStringSync();
    expect(() => jsonDecode(raw), throwsFormatException);
  });

  test('model json roundtrip stable', () {
    final doc = readJsonFixture('examples/cottage-12x8x12.json');
    final r = validateSchematicDoc(doc);
    expect(r.report.ok, isTrue);
    final design = r.design!;
    final again = validateSchematicDoc(
        Design.fromJson(design.toJson()).toJson());
    expect(again.report.ok, isTrue);
    expect(again.design!.blocks.length, design.blocks.length);
    expect(again.design!.palette.length, design.palette.length);
    expect(again.design!.dimensions, design.dimensions);
  });

  test('examples valid triple validates', () {
    for (final n in ['cottage-12x8x12', 'tower-9x18x9', 'arch-bridge-21x9x7']) {
      final r = validateSchematicDoc(readJsonFixture('examples/$n.json'));
      expect(r.report.ok, isTrue, reason: n);
      expect(r.design!.blocks.isNotEmpty, isTrue);
    }
  });
}
