import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repos/import_log_repository.dart';
import '../design_detail/detail_screen.dart';
import '../theme/theme.dart';

class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
    final entries = ref.watch(importLogProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.navLog),
        actions: [
          IconButton(
            tooltip: l.logClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              await ref.read(importLogRepoProvider).clear();
              ref.invalidate(importLogProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.logCleared)));
              }
            },
          ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l.failureDatabase}: $e')),
        data: (rows) => rows.isEmpty
            ? Center(child: Text(l.noIssues))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final e = rows[i];
                  final (color, icon, label) = switch (e.status) {
                    ImportStatus.success => (
                        S3dTheme.mcLime,
                        Icons.check_circle_outline,
                        l.logStatusSuccess
                      ),
                    ImportStatus.partial => (
                        S3dTheme.mcAmber,
                        Icons.warning_amber_rounded,
                        l.logStatusPartial
                      ),
                    ImportStatus.failed => (
                        S3dTheme.danger,
                        Icons.error_outline,
                        l.logStatusFailed
                      ),
                  };
                  final df = DateFormat.yMd().add_jm();
                  return Card(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: ListTile(
                      leading: Icon(icon, color: color),
                      title: Text(e.fileName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${df.format(DateTime.fromMillisecondsSinceEpoch(e.createdAt))} · '
                          '${e.errorCount}E/${e.warningCount}W'
                          '${e.droppedBlocks > 0 ? ' · ${l.infoDropped}: ${e.droppedBlocks}' : ''}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: e.status != ImportStatus.failed &&
                              e.designId != null
                          ? Icon(Icons.chevron_right,
                              color: color.withOpacity(0.7))
                          : null,
                      onTap: () {
                        if (e.designId != null &&
                            e.status != ImportStatus.failed) {
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) =>
                                DetailScreen(designId: e.designId!),
                          ));
                        } else {
                          showDialog<void>(
                            context: context,
                            builder: (bc) => AlertDialog(
                              title: Text(e.fileName),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (e.message != null)
                                      Text(e.message!),
                                    if (e.unsupportedBlocks.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(l
                                          .logUnsupportedN(
                                              e.unsupportedBlocks.length),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      for (final u in e.unsupportedBlocks)
                                        Text('• $u',
                                            style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12)),
                                    ],
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(bc),
                                    child: Text(l.close)),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
