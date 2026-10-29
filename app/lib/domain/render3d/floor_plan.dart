import '../model/design.dart';

/// 2D floor-plan projection: cells for one Y slice (or Y range), with room
/// and layer metadata, for the plan painter. Pure Dart (testable on VM).
class FloorPlan {
  FloorPlan({
    required this.width,
    required this.depth,
    required this.cells,
    required this.levelLabels,
  });

  final int width; // X span
  final int depth; // Z span

  /// palette index + 1 per cell (0 = empty), sized width*depth, index x*depth+z.
  final Int32ListLike cells;
  final List<String> levelLabels;

  int cellAt(int x, int z) => cells[x * depth + z];
  bool isFilled(int x, int z) => cells[x * depth + z] > 0;

  static FloorPlan slice(Design design, int yMin, int yMax) {
    final dx = design.dimensions.$1;
    final dz = design.dimensions.$3;
    final cells = List<int>.filled(dx * dz, 0);
    for (final b in design.blocks) {
      if (b.y < yMin || b.y > yMax) continue;
      if (b.x < 0 || b.z < 0 || b.x >= dx || b.z >= dz) continue;
      cells[b.x * dz + b.z] = b.paletteIndex + 1;
    }
    final levels = <String>[];
    for (final l in design.layers) {
      if (l.yMax >= yMin && l.yMin <= yMax) levels.add(l.displayName);
    }
    return FloorPlan(
      width: dx,
      depth: dz,
      cells: Int32ListLike(cells),
      levelLabels: levels.isEmpty ? ['Y $yMin–$yMax'] : levels,
    );
  }

  /// Layer bands for the side elevation view (layers panel).
  static List<({Layer layer, double frac01Start, double frac01End})> bands(
      Design design) {
    final dy = design.dimensions.$2;
    return [
      for (final l in design.layers)
        (
          layer: l,
          frac01Start: l.yMin / dy,
          frac01End: (l.yMax + 1) / dy,
        ),
    ];
  }

  /// Room footprints overlapping a Y slice.
  static List<({Room room, int x0, int z0, int x1, int z1})> roomsAtY(
      Design design, int y) {
    return [
      for (final r in design.rooms)
        if (r.containsY(y) &&
            (r.layerId == null ||
                design.layerById(r.layerId!)?.covers(y) == true))
          (room: r, x0: r.xMin, z0: r.zMin, x1: r.xMax, z1: r.zMax),
    ];
  }
}

/// Thin wrapper so FloorPlan stays Flutter-free and testable on the VM.
class Int32ListLike {
  Int32ListLike(this.values);
  final List<int> values;
  int operator [](int i) => values[i];
}
