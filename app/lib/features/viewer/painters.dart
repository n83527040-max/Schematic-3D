import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/render3d/floor_plan.dart';
import '../../domain/render3d/voxel_mesh.dart';

/// Painter for the orbit 3D view; consumes VoxelMeshBuilder output directly.
class VoxelPainter extends CustomPainter {
  VoxelPainter({required this.mesh, required this.highlight});

  final ({Float32List points, Int32List colors, MeshStats stats})? mesh;

  /// currently highlighted block (selection), design coords, or null.
  final (int, int, int)? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final m = mesh;
    if (m == null) return;
    final pts = m.points;
    final colors = m.colors;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.35
      ..color = Colors.black.withOpacity(0.18);
    final path = Path();
    final n = colors.length;
    for (var i = 0; i < n; i++) {
      final b = i * 8;
      path
        ..moveTo(pts[b], pts[b + 1])
        ..lineTo(pts[b + 2], pts[b + 3])
        ..lineTo(pts[b + 4], pts[b + 5])
        ..lineTo(pts[b + 6], pts[b + 7])
        ..close();
      fill.color = Color(colors[i]);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
      path.reset();
    }
    if (highlight != null) {
      // bounding box outline of the highlighted block cell
      final h = highlight!;
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFD54F);
      canvas.drawRect(
        Rect.fromLTWH(h.$1.toDouble(), h.$2.toDouble(), 1, 1),
        outline,
      );
    }
  }

  @override
  bool shouldRepaint(VoxelPainter old) =>
      old.mesh != mesh || old.highlight != highlight;
}

/// Painter for the 2D floor plan slice with optional room overlays.
class FloorPlanPainter extends CustomPainter {
  FloorPlanPainter({
    required this.plan,
    required this.cellPx,
    required this.colorForIndex,
    required this.rooms,
    required this.showRooms,
  });

  final FloorPlan plan;
  final double cellPx;
  final int Function(int paletteIdxPlusOne) colorForIndex;

  /// room rectangles (x0,z0,x1,z1) + label
  final List<({int x0, int z0, int x1, int z1, String label})> rooms;
  final bool showRooms;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..style = PaintingStyle.fill;
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withOpacity(0.05);
    for (var x = 0; x < plan.width; x++) {
      for (var z = 0; z < plan.depth; z++) {
        final rect = Rect.fromLTWH(x * cellPx, z * cellPx, cellPx, cellPx);
        canvas.drawRect(rect, hair);
        final v = plan.cellAt(x, z);
        if (v > 0) {
          grid.color = Color(colorForIndex(v));
          canvas.drawRect(rect.deflate(0.4), grid);
        }
      }
    }
    if (showRooms) {
      for (final r in rooms) {
        final rect = Rect.fromLTWH(
          r.x0 * cellPx,
          r.z0 * cellPx,
          (r.x1 - r.x0 + 1) * cellPx,
          (r.z1 - r.z0 + 1) * cellPx,
        );
        final rp = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF80D8FF);
        canvas.drawRect(rect, rp);
        final tp = TextPainter(
          text: TextSpan(
              text: r.label,
              style: const TextStyle(
                  color: Color(0xFF80D8FF), fontSize: 11, height: 1.0)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.topLeft + const Offset(3, 2));
      }
    }
  }

  @override
  bool shouldRepaint(FloorPlanPainter old) =>
      old.plan != plan ||
      old.cellPx != cellPx ||
      old.showRooms != showRooms ||
      old.rooms != rooms;
}
