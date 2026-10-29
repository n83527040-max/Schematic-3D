import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../domain/materials/materials.dart';
import '../../domain/model/design.dart';
import '../../domain/render3d/floor_plan.dart';
import '../../domain/render3d/voxel_mesh.dart';
import '../theme/theme.dart';
import 'painters.dart';

/// The design viewer: orbit 3D + floor-plan slice, layer/room filters.
/// Heavy mesh building is off the widget tree (async microtask + stats).
class DesignViewer extends StatefulWidget {
  const DesignViewer({
    super.key,
    required this.design,
    required this.mode,
    required this.visibleLayers,
    required this.showRooms,
    required this.slice,
    this.onStats,
  });

  final Design design;
  final ViewMode mode;

  /// empty = all visible
  final Set<String> visibleLayers;
  final bool showRooms;
  final (int, int) slice;
  final void Function(MeshStats)? onStats;

  @override
  State<DesignViewer> createState() => _DesignViewerState();
}

class _DesignViewerState extends State<DesignViewer> {
  double _yaw = 0.65, _pitch = 0.5, _zoom = 12;
  ({Float32List points, Int32List colors, MeshStats stats})? _mesh;
  FloorPlan? _plan;
  List<({int x0, int z0, int x1, int z1, String label})> _roomRects = [];
  Timer? _debounce;
  bool _busy = false;
  Int32List _palColors = Int32List(0);

  @override
  void initState() {
    super.initState();
    _paletteColors();
    _rebuild();
  }

  void _paletteColors() {
    _palColors = Int32List(widget.design.palette.length);
    for (var i = 0; i < widget.design.palette.length; i++) {
      _palColors[i] = VoxelMeshBuilder.colorFor(widget.design.palette[i].id);
    }
  }

  @override
  void didUpdateWidget(DesignViewer old) {
    super.didUpdateWidget(old);
    if (old.design != widget.design) _paletteColors();
    if (old.design != widget.design ||
        old.mode != widget.mode ||
        old.visibleLayers != widget.visibleLayers ||
        old.showRooms != widget.showRooms ||
        old.slice != widget.slice) {
      _scheduleRebuild();
    }
  }

  void _scheduleRebuild() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 90), _rebuild);
  }

  bool _blockVisible(BlockEntry b) {
    if (widget.mode == ViewMode.floorPlan) {
      if (b.y < widget.slice.$1 || b.y > widget.slice.$2) return false;
    }
    if (widget.visibleLayers.isNotEmpty) {
      var ok = false;
      for (final l in widget.design.layers) {
        if (l.covers(b.y) && widget.visibleLayers.contains(l.id)) {
          ok = true;
          break;
        }
      }
      if (!ok) return false;
    }
    return true;
  }

  void _rebuild() {
    if (_busy) return;
    _busy = true;
    // build on next frame; for designs < ~120k blocks this is a few ms
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _busy = false;
        return;
      }
      if (widget.mode == ViewMode.threeD) {
        final cam = OrbitCamera(
            yaw: _yaw, pitch: _pitch, pixelsPerBlock: _zoom);
        final res = VoxelMeshBuilder().build(widget.design, cam,
            blockVisible: _blockVisible);
        _mesh = (points: res.points, colors: res.colors, stats: res.stats);
        widget.onStats?.call(res.stats);
      } else {
        _mesh = null;
        _plan = FloorPlan.slice(
            widget.design, widget.slice.$1, widget.slice.$2);
        _roomRects = [
          for (final r in FloorPlan.roomsAtY(
              widget.design, ((widget.slice.$1 + widget.slice.$2) >> 1)))
            (
              x0: r.x0,
              z0: r.z0,
              x1: r.x1,
              z1: r.z1,
              label: r.room.displayName
            ),
        ];
      }
      setState(() {});
      _busy = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      return GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _yaw += d.delta.dx * 0.008;
            _pitch = (_pitch + d.delta.dy * 0.006).clamp(-1.5, 1.5);
          });
          _scheduleRebuild();
        },
        onDoubleTap: () {
          setState(() {
            _yaw = 0.65;
            _pitch = 0.5;
            _zoom = 12;
          });
          _scheduleRebuild();
        },
        onScaleUpdate: (d) {
          if (d.scale != 1.0) {
            setState(() {
              _zoom = (_zoom * d.scale).clamp(2.0, 64.0);
            });
            _scheduleRebuild();
          }
        },
        child: InteractiveViewer(
          maxScale: 6,
          child: CustomPaint(
            size: Size(w, h),
            painter: widget.mode == ViewMode.threeD
                ? VoxelPainter(mesh: _mesh, highlight: null)
                : FloorPlanPainter(
                    plan: _plan ??
                        FloorPlan.slice(widget.design, 0, 0),
                    cellPx: _zoom.clamp(4, 48),
                    colorForIndex: (v) {
                      final i = v - 1;
                      return i >= 0 && i < _palColors.length
                          ? _palColors[i]
                          : 0xFF96969B;
                    },
                    rooms: _roomRects,
                    showRooms: widget.showRooms,
                  ),
          ),
        ),
      );
    });
  }
}

/// Materials list panel for the design (block-data-derived only).
class MaterialsPanel extends StatelessWidget {
  const MaterialsPanel({super.key, required this.design});
  final Design design;

  @override
  Widget build(BuildContext context) {
    final mats = Materials.fromDesign(design);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('${l10n(context).totalBlocks}: ${mats.totalBlocks}',
            style: Theme.of(context).textTheme.titleSmall),
        Text('${l10n(context).distinctMaterials}: ${mats.distinctTypes}'),
        const SizedBox(height: 12),
        for (final l in mats.detailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Color(VoxelMeshBuilder.colorFor(l.id)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.id, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Text(
                          '${l10n(context).blockCount}: ${l.count} · '
                          '${l10n(context).stacks}: ${l.stacks}'
                          '${l.remainder == 0 ? '' : ' + ${l.remainder}'}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
