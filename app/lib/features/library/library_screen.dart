import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/constants.dart';
import '../../data/repos/design_repository.dart';
import '../../data/services/addon_packer.dart';
import '../design_detail/detail_screen.dart';
import '../prompt/prompt_sheet.dart';
import '../theme/theme.dart';
import '../../l10n/generated/app_localizations.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          if (lib.selected.isNotEmpty) ...[
            IconButton(
              tooltip: l.exportAddon,
              icon: const Icon(Icons.archive_outlined),
              onPressed: () => _exportSelection(lib),
            ),
            IconButton(
              tooltip: l.moveCategory,
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () => _moveSelection(lib.selected.toList()),
            ),
            IconButton(
              tooltip: l.close,
              icon: const Icon(Icons.deselect),
              onPressed: () =>
                  ref.read(libraryProvider.notifier).clearSelection(),
            ),
          ] else
            IconButton(
              tooltip: l.sortLabel,
              icon: const Icon(Icons.sort),
              onPressed: _showSortSheet,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: l.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtl.clear();
                          ref.read(libraryProvider.notifier).setSearch(null);
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (v) {
                setState(() {});
                ref.read(libraryProvider.notifier).setSearch(v);
              },
            ),
          ),
          _CategoryBar(onFolderTap: (k) {
            ref.read(libraryProvider.notifier).setCategory(k);
          }),
          Expanded(
            child: lib.loading
                ? const Center(child: CircularProgressIndicator())
                : lib.rows.isEmpty
                    ? const _EmptyLibrary()
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(libraryProvider.notifier).refresh(),
                        child: ListView.builder(
                          itemCount: lib.rows.length + 1,
                          itemBuilder: (context, i) {
                            if (i == lib.rows.length) {
                              return Padding(
                                padding: const EdgeInsets.all(10),
                                child: Center(
                                  child: Text(
                                    l.libraryCount(lib.rows.length),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              );
                            }
                            final row = lib.rows[i];
                            final sel = lib.selected.contains(row.id);
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: sel
                                      ? S3dTheme.mcLime
                                      : S3dTheme.novaLine,
                                  width: sel ? 2 : 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        DetailScreen(designId: row.id),
                                  ),
                                ),
                                onLongPress: () => ref
                                    .read(libraryProvider.notifier)
                                    .toggleSelect(row.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      _MiniPreview(row: row),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(row.name,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${row.dimX}×${row.dimY}×${row.dimZ} · '
                                              '${row.blockCount} ${l.blockCount}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            if (row.droppedBlocks > 0)
                                              Text(
                                                '${l.infoDropped}: ${row.droppedBlocks}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                        color:
                                                            S3dTheme.mcAmber),
                                              ),
                                            if (row.categoryKey != null)
                                              Text(
                                                _categoryLabel(row.categoryKey!),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                      Checkbox(
                                        value: sel,
                                        onChanged: (_) => ref
                                            .read(libraryProvider.notifier)
                                            .toggleSelect(row.id),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'promptFabLibrary',
        tooltip: l.promptFab,
        onPressed: () => showPromptSheet(context, design: null),
        child: const Icon(Icons.auto_awesome),
      ),
    );
  }

  String _categoryLabel(String key) {
    final l = l10n(context);
    return switch (key) {
      'palaces' => l.categoryPalaces,
      'houses' => l.categoryHouses,
      'towers' => l.categoryTowers,
      'bridges' => l.categoryBridges,
      'farms' => l.categoryFarms,
      'decor' => l.categoryDecor,
      'industrial' => l.categoryIndustrial,
      _ => l.categoryOther,
    };
  }

  void _showSortSheet() {
    final l = l10n(context);
    final settings = ref.read(settingsProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in const [
              (SortKey.name, 'sortByName'),
              (SortKey.size, 'sortBySize'),
              (SortKey.blocks, 'sortByBlocks'),
              (SortKey.date, 'sortByDate'),
            ])
              RadioListTile<SortKey>(
                title: Text(e.$2 == 'sortByName'
                    ? l.sortByName
                    : e.$2 == 'sortBySize'
                        ? l.sortBySize
                        : e.$2 == 'sortByBlocks'
                            ? l.sortByBlocks
                            : l.sortByDate),
                value: e.$1,
                groupValue: settings.sortKey,
                onChanged: (v) {
                  settings.sortKey = v!;
                  ref.read(libraryProvider.notifier).refresh();
                  Navigator.pop(bc);
                },
              ),
            SwitchListTile(
              title: Text(l.sortDescending),
              value: settings.sortDescending,
              onChanged: (v) {
                settings.sortDescending = v;
                ref.read(libraryProvider.notifier).refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveSelection(List<int> ids) async {
    final l = l10n(context);
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (bc) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final k in kCategoryKeys)
              ListTile(
                leading: Text(kCategoryEmoji[k] ?? '📁',
                    style: const TextStyle(fontSize: 20)),
                title: Text(switch (k) {
                  'palaces' => l.categoryPalaces,
                  'houses' => l.categoryHouses,
                  'towers' => l.categoryTowers,
                  'bridges' => l.categoryBridges,
                  'farms' => l.categoryFarms,
                  'decor' => l.categoryDecor,
                  'industrial' => l.categoryIndustrial,
                  _ => l.categoryOther,
                }),
                onTap: () => Navigator.pop(bc, k),
              ),
          ],
        ),
      ),
    );
    if (key == null) return;
    final repo = ref.read(designRepoProvider);
    for (final id in ids) {
      await repo.setCategory(id, key);
    }
    ref.read(libraryProvider.notifier).clearSelection();
    await ref.read(libraryProvider.notifier).refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.ok)));
    }
  }

  Future<void> _exportSelection(LibraryState lib) async {
    final l = l10n(context);
    final repo = ref.read(designRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final rows = <DesignRow>[];
    for (final id in lib.selected) {
      final r = await repo.byId(id);
      if (r != null) rows.add(r);
    }
    if (rows.isEmpty) return;
    messenger.showSnackBar(SnackBar(content: Text(l.exportAddonBuilding)));
    try {
      final outDir = await exportsDir();
      final file = await ref.read(addonPackerProvider).build(
            outName: 'Schematic3D_library.mcaddon',
            designs: [
              for (final r in rows)
                PackDesign(
                  id: r.name,
                  name: r.name,
                  design: r.decodeDesign(),
                  droppedBlocks: r.droppedBlocks,
                  sourceFormat: r.sourceFormat ?? 'json',
                ),
            ],
            outDir: outDir,
          );
      await ref.read(fileIoProvider).shareFile(file.path,
          subject: 'Schematic3D_library.mcaddon');
      ref.read(libraryProvider.notifier).clearSelection();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${l.failureExport}: $e')));
    }
  }
}

class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.row});
  final DesignRow row;

  @override
  Widget build(BuildContext context) {
    // tiny schematic-ish glyph sized by proportions (no heavy render in list)
    final dx = row.dimX, dy = row.dimY, dz = row.dimZ;
    final maxDim = [dx, dy, dz].reduce((a, b) => a > b ? a : b);
    final w = (dx / maxDim * 34).clamp(10.0, 34.0);
    final h = (dy / maxDim * 34).clamp(10.0, 34.0);
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [S3dTheme.mcGrass, S3dTheme.novaLine],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: S3dTheme.mcLime.withOpacity(0.5)),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();
  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dashboard_customize_outlined,
                size: 56, color: S3dTheme.mcLime),
            const SizedBox(height: 12),
            Text(l.emptyLibrary,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l.emptyLibraryHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({required this.onFolderTap});
  final void Function(String?) onFolderTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
    final current = ref.read(libraryProvider.notifier).category;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              label: Text(l.categoryAll),
              selected: current == null,
              onSelected: (_) => onFolderTap(null),
            ),
          ),
          for (final k in kCategoryKeys)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                label: Text('${kCategoryEmoji[k]} ${_label(l, k)}'),
                selected: current == k,
                onSelected: (_) => onFolderTap(k),
              ),
            ),
        ],
      ),
    );
  }

  String _label(AppLocalizations l, String k) => switch (k) {
        'palaces' => l.categoryPalaces,
        'houses' => l.categoryHouses,
        'towers' => l.categoryTowers,
        'bridges' => l.categoryBridges,
        'farms' => l.categoryFarms,
        'decor' => l.categoryDecor,
        'industrial' => l.categoryIndustrial,
        _ => l.categoryOther,
      };
}
