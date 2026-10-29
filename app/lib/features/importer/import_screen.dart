import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/formats/design_importer.dart';
import '../../domain/validation/design_validator.dart';
import '../theme/theme.dart';

/// Import tab: pick → convert → report → auto-save (or discard).
/// On failure the ORIGINAL file copy is persisted + logged (spec §5).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});
  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;
  ImportOutcome? _outcome;
  String _fileName = '';

  Future<void> _pick() async {
    final picked = await ref.read(fileIoProvider).pickDesignFile();
    if (picked == null) return;
    setState(() {
      _busy = true;
      _outcome = null;
      _fileName = picked.name;
    });
    try {
      final outcome = await ref
          .read(importServiceProvider)
          .importFromBytes(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _busy = false;
      });
      await ref.read(libraryProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${l10n(context).failureExport}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    final o = _outcome;
    return Scaffold(
      appBar: AppBar(title: Text(l.navImport)),
      body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: Text(l.importPick),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                side: const BorderSide(color: S3dTheme.mcLime, width: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(l.importPickHint,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (_busy)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text('${l.importWorking} $_fileName'),
                ],
              ),
            if (o != null) _ImportReport(outcome: o, fileName: _fileName),
          ],
        ),
    );
  }
}

class _ImportReport extends ConsumerWidget {
  const _ImportReport({required this.outcome, required this.fileName});
  final ImportOutcome outcome;
  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
    final rep = outcome.report;
    final ok = outcome.ok;
    final status = !ok
        ? (rep.errors.any((e) => e.code == 'format.unknown')
            ? l.failureUnsupportedFormat
            : l.importResultFailed)
        : rep.warnings.isEmpty
            ? l.importResultOk
            : l.importResultPartial;
    final color = !ok
        ? S3dTheme.danger
        : rep.warnings.isEmpty
            ? S3dTheme.mcLime
            : S3dTheme.mcAmber;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.error_outline,
                    color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$status',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(fileName,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            if (!ok) ...[
              const SizedBox(height: 8),
              Text(l.importFailKept,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (rep.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.errorsTitle,
                  style: Theme.of(context).textTheme.titleSmall),
              for (final e in rep.errors.take(30)) _issueTile(context, e, true),
            ],
            if (rep.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.warningsTitle,
                  style: Theme.of(context).textTheme.titleSmall),
              for (final w in rep.warnings.take(30))
                _issueTile(context, w, false),
            ],
            if (outcome.conversion?.unsupportedBlocks.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text(l.unsupportedTitle,
                  style: Theme.of(context).textTheme.titleSmall),
              Text(l.unsupportedHint,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in outcome.conversion!.unsupportedBlocks)
                    Chip(
                      label: Text(id,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11)),
                    ),
                ],
              ),
            ],
            if (outcome.conversion != null) ...[
              const SizedBox(height: 8),
              Text(
                '${l.infoDropped}: ${outcome.conversion!.droppedBlocks} · '
                'format: ${outcome.format.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _issueTile(BuildContext context, Issue e, bool isError) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(isError ? Icons.cancel : Icons.warning_amber,
          size: 18, color: isError ? S3dTheme.danger : S3dTheme.mcAmber),
      title: Text(e.message, style: const TextStyle(fontSize: 13)),
      subtitle: Text(e.code,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
    );
  }
}
