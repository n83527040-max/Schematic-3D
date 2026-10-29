import 'dart:math' as math;

import '../model/design.dart';

/// Material requirements computed from block data ONLY (spec §6: never from
/// AI text claims). Mirrors converter materials.py semantics.
class Materials {
  Materials(this.lines, this.totalBlocks);

  /// (bedrockId, count) sorted by count desc then id asc.
  final List<(String id, int count)> lines;
  final int totalBlocks;

  bool get isEmpty => lines.isEmpty;

  int get distinctTypes => lines.length;

  static Materials fromDesign(Design design) {
    final counts = <int, int>{};
    for (final b in design.blocks) {
      counts[b.paletteIndex] = (counts[b.paletteIndex] ?? 0) + 1;
    }
    final lines = <(String, int)>[];
    for (final e in counts.entries) {
      if (e.key < 0 || e.key >= design.palette.length) continue;
      lines.add((design.palette[e.key].id, e.value));
    }
    lines.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return Materials(lines, design.blocks.length);
  }

  /// Per-material totals + the number of full 64-stacks a builder needs —
  /// shown in the UI and used by the add-on's inventory gate.
  List<MaterialLine> get detailed => [
        for (final l in lines)
          MaterialLine(l.$1, l.$2, (l.$2 / 64).ceil(), l.$2 % 64),
      ];

  Map<String, Object?> toJson() => {
        'total': totalBlocks,
        'distinct': distinctTypes,
        'lines': [
          for (final l in lines) {'id': l.$1, 'count': l.$2},
        ],
      };
}

class MaterialLine {
  const MaterialLine(this.id, this.count, this.stacks, this.remainder);
  final String id;
  final int count;
  final int stacks;
  final int remainder;

  @override
  String toString() => '$id × $count ($stacks × 64${remainder == 0 ? '' : ' + $remainder'})';
}

int maxStackFor(String id) => math.max(1, 64); // display helper
