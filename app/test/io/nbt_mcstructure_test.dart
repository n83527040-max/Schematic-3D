import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:schematic_3d/domain/formats/mcstructure_codec.dart';
import 'package:schematic_3d/domain/nbt/nbt.dart';

import '../helpers.dart';

void main() {
  group('NBT', () {
    test('read/write roundtrip preserves a compound', () {
      final root = <String, Object?>{
        'i': const NbtInt(42),
        'l': const NbtLong(-9007199254740991),
        's': 'héllo ✓',
        'b': Uint8List.fromList([1, 2, 255 - 256 + 128, 0]),
        'list': NbtList(tagCompound, [
          {'n': const NbtInt(1), 't': 'a'},
          {'n': const NbtInt(2), 't': 'b'},
        ]),
        'ia': [10, 20, 30] as List<int>,
        'f': 3.5,
      };
      final bytes = writeNbtBytes(root, littleEndian: true);
      final back = readNbt(bytes, littleEndian: true);
      final r = back.root;
      expect((r['i'] as NbtInt).value, 42);
      expect((r['l'] as NbtLong).value, -9007199254740991);
      expect(r['s'], 'héllo ✓');
      expect((r['ia'] as List<int>).toList(), [10, 20, 30]);
      expect(r['f'], closeTo(3.5, 1e-6));
      final list = r['list'] as NbtList;
      expect(list.items.length, 2);
      expect(((list.items[1] as Map)['n'] as NbtInt).value, 2);
    });

    test('big-endian variant roundtrips too', () {
      final root = <String, Object?>{'x': const NbtInt(-777)};
      final bytes = writeNbtBytes(root, littleEndian: false);
      final back = readNbt(bytes, littleEndian: false);
      expect((back.root['x'] as NbtInt).value, -777);
    });
  });

  group('mcstructure codec', () {
    for (final name in [
      'cottage-12x8x12',
      'tower-9x18x9',
      'arch-bridge-21x9x7',
    ]) {
      test('$name parses from .mcstructure (vanilla layout)', () {
        final bytes = File(fixture('examples/$name.mcstructure'))
            .readAsBytesSync();
        final r = McstructureCodec.parse(bytes, sourceName: name);
        expect(r.report.ok, isTrue, reason: r.report.issues.toString());
        expect(r.design!.blocks.isNotEmpty, isTrue);
        expect(r.design!.name, name);
      });
    }

    test('encode→parse roundtrip keeps geometry and palette', () {
      final bytes =
          File(fixture('examples/tower-9x18x9.mcstructure')).readAsBytesSync();
      final first = McstructureCodec.parse(bytes, sourceName: 'tower');
      final design = first.design!;
      final reBytes = McstructureCodec.encode(design);
      final second = McstructureCodec.parse(reBytes, sourceName: 'tower');
      expect(second.report.ok, isTrue);
      final d2 = second.design!;
      expect(d2.dimensions, design.dimensions);
      expect(d2.blocks.length, design.blocks.length);
      // block positions identical (sort by key)
      int cmp((int, int, int) x, (int, int, int) y) => x.$1 != y.$1
          ? x.$1.compareTo(y.$1)
          : x.$2 != y.$2
              ? x.$2.compareTo(y.$2)
              : x.$3.compareTo(y.$3);
      final a = [for (final b in design.blocks) b.key]..sort(cmp);
      final b2 = [for (final b in d2.blocks) b.key]..sort(cmp);
      expect(b2, a);
    });

    test('real Forest-of-Light tower parses (external reference file)', () {
      final file = File(fixture('converter/tests/fixtures/forest-tower.mcstructure'));
      expect(file.existsSync(), isTrue);
      final r = McstructureCodec.parse(file.readAsBytesSync(),
          sourceName: 'forest-tower');
      expect(r.report.ok, isTrue, reason: r.report.issues.toString());
      expect(r.design!.dimensions, (17, 19, 17));
      expect(r.design!.blocks.length, greaterThan(900));
    });
  });
}
