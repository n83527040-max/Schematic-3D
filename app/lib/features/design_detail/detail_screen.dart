import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/constants.dart';
import '../../data/repos/design_repository.dart';
import '../../data/services/addon_packer.dart';
import '../../domain/formats/mcstructure_codec.dart';
import '../../domain/model/design.dart';
import '../../domain/render3d/voxel_mesh.dart' show MeshStats;
import '../../l10n/generated/app_localizations.dart';
import '../prompt/prompt_sheet.dart';
import '../theme/theme.dart';
import '../viewer/design_viewer.dart';

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.designId});
  final int designId;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  Set<String> _selectedLayers = {};
  bool _showRooms = true;
  int _sliceLo = 0, _sliceHi = 0;
  MeshStats? _stats;
  DesignRow? _row;
  Design? _design;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = await ref.read(designRepoProvider).byId(widget.designId);
    if (!mounted) return;
    setState(() {
      _row = row;
      _design = row?.decodeDesign();
      if (_design != null) {
        _sliceLo = 0;
        _sliceHi = _design!.dimensions.$2 - 1;
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    final row = _row;
    final design = _design;
    if (row == null || design == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final viewer = (ViewMode mode) => Column(
          children: [
            if (mode == ViewMode.threeD && _stats != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Text(
                  '${_stats!.quads} quads · ${_stats!.culled} culled · '
                  '${(_stats!.buildMicros / 1000).toStringAsFixed(1)} ms',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            Expanded(
              child: DesignViewer(
                design: design,
                mode: mode,
                visibleLayers: _selectedLayers,
                showRooms: _showRooms,
                slice: (_sliceLo, _sliceHi),
                onStats: (s) => setState(() => _stats = s),
              ),
            ),
          ],
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(row.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l.renameAction,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(row),
          ),
          IconButton(
            tooltip: l.moveCategory,
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: () => _move(row.id),
          ),
          PopupMenuButton<String>(
            tooltip: l.exportAddon,
            icon: const Icon(Icons.ios_share),
            onSelected: (v) => _export(row, design, v),
            itemBuilder: (bc) => [
              PopupMenuItem(value: 'json', child: Text(l.exportJson)),
              PopupMenuItem(
                  value: 'mcstructure', child: Text(l.exportMcstructure)),
              PopupMenuItem(value: 'addon', child: Text(l.exportAddon)),
            ],
          ),
          IconButton(
            tooltip: l.deleteAction,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(row.id),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l.detailTab3d),
            Tab(text: l.detailTabPlan),
            Tab(text: l.detailTabMaterials),
            Tab(text: l.detailTabInfo),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          viewer(ViewMode.threeD),
          viewer(ViewMode.floorPlan),
          MaterialsPanel(design: design),
          _infoTab(row, design),
        ],
      ),
      bottomNavigationBar: _controlBar(design),
      floatingActionButton: FloatingActionButton(
        heroTag: 'promptFabDetail',
        tooltip: l.promptFab,
        onPressed: () => showPromptSheet(context, design: design),
        child: const Icon(Icons.auto_awesome),
      ),
    );
  }

  Widget _controlBar(Design design) {
    final l = l10n(context);
    final dy = design.dimensions.$2;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (design.layers.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final layer in design.layers)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: FilterChip(
                        label: Text(
                            '${layer.displayName} (${layer.yMin}–${layer.yMax})'),
                        selected: _selectedLayers.isEmpty ||
                            _selectedLayers.contains(layer.id),
                        onSelected: (_) => setState(() {
                          final sel = {..._selectedLayers};
                          if (!sel.add(layer.id)) sel.remove(layer.id);
                          if (sel.length == design.layers.length) sel.clear();
                          _selectedLayers = sel;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: l.resetView,
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() {
                  _selectedLayers = {};
                  _showRooms = true;
                  _sliceLo = 0;
                  _sliceHi = dy - 1;
                }),
              ),
              IconButton(
                tooltip: l.roomsTitle,
                icon: Icon(_showRooms
                    ? Icons.meeting_room_outlined
                    : Icons.meeting_room),
                onPressed: () => setState(() => _showRooms = !_showRooms),
              ),
              Expanded(
                child: RangeSlider(
                  min: 0,
                  max: (dy - 1).toDouble().clamp(0, double.maxFinite),
                  values: RangeValues(
                    _sliceLo.toDouble().clamp(0, (dy - 1).toDouble()),
                    _sliceHi.toDouble().clamp(0, (dy - 1).toDouble()),
                  ),
                  onChanged: dy <= 1
                      ? null
                      : (v) => setState(() {
                            _sliceLo = v.start.round();
                            _sliceHi = v.end.round();
                          }),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(l.sliceRange(_sliceLo, _sliceHi),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _infoTab(DesignRow row, Design design) {
    final l = l10n(context);
    final dims = design.dimensions;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kv(context, l.infoName, row.name),
        if (design.description != null)
          _kv(context, l.infoDescription, design.description!),
        _kv(context, l.infoSource,
            '${row.sourceFormat ?? 'json'} · ${row.blockCount} ${l.blockCount}'),
        _kv(context, l.infoDims, '${dims.$1} × ${dims.$2} × ${dims.$3}'),
        _kv(context, l.infoPalette, '${design.palette.length}'),
        if (design.rooms.isNotEmpty)
          _kv(context, l.roomsTitle, design.rooms.map((r) => r.displayName).join(' · ')),
        if (row.droppedBlocks > 0)
          _kv(context, l.infoDropped, '${row.droppedBlocks}'),
        if ((row.notes ?? '').isNotEmpty) _kv(context, l.infoNotes, row.notes!),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k, style: Theme.of(context).textTheme.labelLarge),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  // ---------------- actions -------------------------------------------
  Future<void> _rename(DesignRow row) async {
    final l = l10n(context);
    final ctl = TextEditingController(text: row.name);
    final name = await showDialog<String>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text(l.renameAction),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(bc), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(bc, ctl.text.trim()),
              child: Text(l.ok)),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(designRepoProvider).rename(row.id, name);
      ref.read(libraryProvider.notifier).refresh();
      await _load();
    }
  }

  Future<void> _move(int id) async {
    final l = l10n(context);
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in kCategoryKeys)
              ListTile(
                leading: Text(kCategoryEmoji[k] ?? '📁',
                    style: const TextStyle(fontSize: 20)),
                title: Text(_categoryLabel(l, k)),
                onTap: () => Navigator.pop(bc, k),
              ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l.categoryAll),
              onTap: () => Navigator.pop(bc, '__none__'),
            ),
          ],
        ),
      ),
    );
    if (key == null) return;
    await ref
        .read(designRepoProvider)
        .setCategory(id, key == '__none__' ? null : key);
    ref.read(libraryProvider.notifier).refresh();
  }

  static String _categoryLabel(AppLocalizations l, String k) => switch (k) {
        'palaces' => l.categoryPalaces,
        'houses' => l.categoryHouses,
        'towers' => l.categoryTowers,
        'bridges' => l.categoryBridges,
        'farms' => l.categoryFarms,
        'decor' => l.categoryDecor,
        'industrial' => l.categoryIndustrial,
        _ => l.categoryOther,
      };

  Future<void> _delete(int id) async {
    final l = l10n(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text(l.confirmDelete),
        content: Text(l.confirmDeleteMsg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(bc, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(bc, true),
              child: Text(l.deleteAction)),
        ],
      ),
    );
    if (yes == true) {
      await ref.read(designRepoProvider).delete(id);
      if (mounted) Navigator.pop(context);
      ref.read(libraryProvider.notifier).refresh();
    }
  }

  Future<void> _export(DesignRow row, Design design, String kind) async {
    final l = l10n(context);
    final messenger = ScaffoldMessenger.of(context);
    final safeName = p.basenameWithoutExtension(row.name)
        .replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
    try {
      if (kind == 'json') {
        final path = await ref
            .read(fileIoProvider)
            .saveTextFile('$safeName.json', row.json);
        await ref.read(fileIoProvider).shareFile(path, subject: '$safeName.json');
      } else if (kind == 'mcstructure') {
        final bytes = McstructureCodec.encode(design);
        final path = await ref
            .read(fileIoProvider)
            .saveBytes('$safeName.mcstructure', bytes);
        await ref
            .read(fileIoProvider)
            .shareFile(path, subject: '$safeName.mcstructure');
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l.exportAddonBuilding)));
        final outDir = await exportsDir();
        final file = await ref.read(addonPackerProvider).build(
              outName: 'Schematic3D_${AddonPacker.sanitizeId(row.name)}.mcaddon',
              designs: [
                PackDesign(
                  id: row.name,
                  name: row.name,
                  design: design,
                  droppedBlocks: row.droppedBlocks,
                  sourceFormat: row.sourceFormat ?? 'json',
                ),
              ],
              outDir: outDir,
            );
        await ref
            .read(fileIoProvider)
            .shareFile(file.path, subject: '$safeName.mcaddon');
        messenger.showSnackBar(SnackBar(content: Text(l.exportAddonShareHint)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${l.failureExport}: $e')));
    }
  }
}
