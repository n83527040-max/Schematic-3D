import 'dart:math' as math;
import 'dart:typed_data';

import '../formats/mapper.dart';
import '../model/design.dart';

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Camera parameters for the orbit-style 3D viewer.
class OrbitCamera {
  OrbitCamera({
    required this.yaw,
    required this.pitch,
    required this.pixelsPerBlock,
    this.viewWidth = 300,
    this.viewHeight = 300,
  });

  /// radians; 0 looks along −Z.
  final double yaw;

  /// radians; clamped to ±(π/2 − 0.02).
  final double pitch;
  final double pixelsPerBlock;
  final double viewWidth;
  final double viewHeight;

  double get clampedPitch => math.min(math.max(pitch, -1.54), 1.54);
}

class MeshStats {
  const MeshStats(this.quads, this.culled, this.buildMicros);
  final int quads;
  final int culled;
  final int buildMicros;

  Map<String, Object?> toJson() =>
      {'quads': quads, 'culled': culled, 'build_us': buildMicros};

  @override
  String toString() =>
      'MeshStats(quads: $quads, culled: $culled, build_us: $buildMicros)';
}

/// Orthographic voxel mesh with hidden-face culling + painter's algorithm.
/// Pure math (no Flutter imports) so unit tests run on the Dart VM.
class VoxelMeshBuilder {
  const VoxelMeshBuilder();

  /// Flat arrays for a CustomPainter: `points` 8 doubles per quad
  /// (screen px of the 4 corners), `colors` ARGB per quad, far→near order.
  ({Float32List points, Int32List colors, MeshStats stats}) build(
    Design design,
    OrbitCamera cam, {
    bool Function(BlockEntry b)? blockVisible,
    int maxQuads = 300000,
  }) {
    final t0 = DateTime.now().microsecondsSinceEpoch;
    final dx = design.dimensions.$1;
    final dy = design.dimensions.$2;
    final dz = design.dimensions.$3;

    final occ = Uint8List(dx * dy * dz);
    for (final b in design.blocks) {
      if (b.x < 0 || b.y < 0 || b.z < 0 ||
          b.x >= dx || b.y >= dy || b.z >= dz) {
        continue;
      }
      occ[(b.x * dy + b.y) * dz + b.z] = 1;
    }

    // per-palette-entry color, computed once
    final colors0 = Int32List(design.palette.length);
    for (var i = 0; i < design.palette.length; i++) {
      colors0[i] = VoxelMeshBuilder.colorFor(design.palette[i].id);
    }

    final cy = math.cos(cam.yaw), sy = math.sin(cam.yaw);
    final cp = math.cos(cam.clampedPitch), sp = math.sin(cam.clampedPitch);
    final cx = dx / 2 - 0.5, ccy = dy / 2 - 0.5, cz = dz / 2 - 0.5;
    final scale = cam.pixelsPerBlock;
    final hw = cam.viewWidth / 2, hh = cam.viewHeight / 2;

    _V3 toView(double x, double y, double z) {
      final vx = x - cx, vy = y - ccy, vz = z - cz;
      final rx = vx * cy - vz * sy;
      final rz = vx * sy + vz * cy;
      final ry = vy * cp - rz * sp;
      final depth = vy * sp + rz * cp;
      return _V3(rx, ry, depth);
    }

    final rawPts = <double>[];
    final rawCol = <int>[];
    final rawDepth = <double>[];
    var culled = 0;
    var made = 0;

    const dirs = [
      (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1),
    ];

    outer:
    for (final b in design.blocks) {
      if (b.x < 0 || b.y < 0 || b.z < 0 ||
          b.x >= dx || b.y >= dy || b.z >= dz) {
        continue;
      }
      if (blockVisible != null && !blockVisible(b)) continue;
      final color = colors0[b.paletteIndex];
      for (final d in dirs) {
        final nx = b.x + d.$1, ny = b.y + d.$2, nz = b.z + d.$3;
        final inside = nx >= 0 && ny >= 0 && nz >= 0 && nx < dx && ny < dy && nz < dz;
        if (inside && occ[(nx * dy + ny) * dz + nz] == 1) {
          culled++;
          continue;
        }
        // backface test: face center must be nearer than block center
        final c = toView(b.x + 0.5, b.y + 0.5, b.z + 0.5);
        final f = toView(b.x + 0.5 + d.$1 * 0.5, b.y + 0.5 + d.$2 * 0.5,
            b.z + 0.5 + d.$3 * 0.5);
        if (f.z >= c.z) continue;

        final corners = _faceCorners(b, d);
        var depthSum = 0.0;
        for (final c2 in corners) {
          final v = toView(c2.x, c2.y, c2.z);
          depthSum += v.z;
          rawPts.add(hw + v.x * scale);
          rawPts.add(hh - v.y * scale);
        }
        rawCol.add(color);
        rawDepth.add(depthSum / 4);
        made++;
        if (made >= maxQuads) break outer;
      }
    }

    final order = List<int>.generate(made, (i) => i)
      ..sort((a, b) => rawDepth[b].compareTo(rawDepth[a])); // far first

    final points = Float32List(made * 8);
    final colors = Int32List(made);
    for (var i = 0; i < made; i++) {
      final q = order[i];
      points.setRange(i * 8, i * 8 + 8, rawPts, q * 8);
      colors[i] = rawCol[q];
    }
    return (
      points: points,
      colors: colors,
      stats: MeshStats(made, culled,
          DateTime.now().microsecondsSinceEpoch - t0),
    );
  }

  static List<_V3> _faceCorners(BlockEntry b, (int, int, int) d) {
    final x = b.x.toDouble(), y = b.y.toDouble(), z = b.z.toDouble();
    if (d.$1 != 0) {
      final px = d.$1 > 0 ? x + 1 : x;
      return [
        _V3(px, y, z), _V3(px, y + 1, z),
        _V3(px, y + 1, z + 1), _V3(px, y, z + 1)
      ];
    }
    if (d.$2 != 0) {
      final py = d.$2 > 0 ? y + 1 : y;
      return [
        _V3(x, py, z), _V3(x + 1, py, z),
        _V3(x + 1, py, z + 1), _V3(x, py, z + 1)
      ];
    }
    final pz = d.$3 > 0 ? z + 1 : z;
    return [
      _V3(x, y, pz), _V3(x + 1, y, pz),
      _V3(x + 1, y + 1, pz), _V3(x, y + 1, pz)
    ];
  }

  /// ARGB color for a Bedrock id via the shared ghost-tint classification.
  static int colorFor(String bedrockId) {
    final tint = Mapper.ghostTintFor(bedrockId) ?? 'ghost_gray';
    return _argb[tint] ?? 0xFF96969B;
  }

  static const _argb = <String, int>{
    'ghost_white': 0xFFEDEDF5,
    'ghost_gray': 0xFF96969B,
    'ghost_black': 0xFF28282D,
    'ghost_wood': 0xFFB28A52,
    'ghost_stone': 0xFF82807D,
    'ghost_sand': 0xFFDACD96,
    'ghost_glass': 0xB0BEE4EB,
    'ghost_red': 0xFFBE3C37,
    'ghost_green': 0xFF509B41,
    'ghost_blue': 0xFF4664C8,
    'ghost_metal': 0xFFD2D2D7,
    'ghost_glow': 0xFFFADC78,
  };
}
