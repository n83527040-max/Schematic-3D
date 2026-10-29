import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/constants.dart';
import '../theme/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- language ---------------------------------------------------
          Text(l.settingsLanguage,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: '', label: Text(l.languageSystem)),
              const ButtonSegment(value: 'ar', label: Text('العربية')),
              const ButtonSegment(value: 'fr', label: Text('Français')),
              const ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {s.languageOverride},
            onSelectionChanged: (v) {
              s.languageOverride = v.first;
            },
          ),
          const Divider(height: 28),
          // ---- default view mode ------------------------------------------
          Text(l.settingsDefaultView,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<ViewMode>(
            segments: [
              ButtonSegment(
                  value: ViewMode.threeD,
                  label: Text(l.detailTab3d),
                  icon: const Icon(Icons.view_in_ar_outlined)),
              ButtonSegment(
                  value: ViewMode.floorPlan,
                  label: Text(l.detailTabPlan),
                  icon: const Icon(Icons.grid_view_outlined)),
            ],
            selected: {s.defaultViewMode},
            onSelectionChanged: (v) => s.defaultViewMode = v.first,
          ),
          const Divider(height: 28),
          // ---- sort ---------------------------------------------------------
          Text(l.sortLabel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final e in SortKey.values)
                ChoiceChip(
                  label: Text(switch (e) {
                    SortKey.name => l.sortByName,
                    SortKey.size => l.sortBySize,
                    SortKey.blocks => l.sortByBlocks,
                    SortKey.date => l.sortByDate,
                  }),
                  selected: s.sortKey == e,
                  onSelected: (_) {
                    s.sortKey = e;
                    ref.read(libraryProvider.notifier).refresh();
                  },
                ),
            ],
          ),
          const Divider(height: 28),
          // ---- batch speed default ------------------------------------------
          Text(l.settingsBatchSpeed,
              style: Theme.of(context).textTheme.titleSmall),
          Text(l.settingsBatchSpeedHint,
              style: Theme.of(context).textTheme.bodySmall),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: 1,
                  max: 256,
                  divisions: 16,
                  value: s.batchSpeed.toDouble(),
                  label: '${s.batchSpeed}/t',
                  onChanged: (v) => s.batchSpeed = v.round(),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text('${s.batchSpeed} ${l.blockCount}',
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ],
          ),
          const Divider(height: 28),
          // ---- safety invariant ----------------------------------------------
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_user_outlined,
                color: S3dTheme.mcLime),
            title: Text(l.settingsConfirmTitle),
            subtitle: Text(l.settingsConfirmAlways),
            trailing: const Icon(Icons.lock_outline, size: 18),
          ),
          const Divider(height: 28),
          // ---- about -----------------------------------------------------------
          Text(l.settingsAbout,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(l.settingsAboutText,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
