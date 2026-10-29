import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/model/design.dart';
import '../theme/theme.dart';

/// The circular-FAB flow (spec §10): compose the external-AI design prompt
/// (+ optional current design JSON) and COPY to clipboard. No network, no
/// in-app AI — this is the only "AI" surface in the product.
Future<void> showPromptSheet(BuildContext context, {Design? design}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PromptSheet(design: design),
  );
}

class _PromptSheet extends ConsumerStatefulWidget {
  const _PromptSheet({this.design});
  final Design? design;
  @override
  ConsumerState<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends ConsumerState<_PromptSheet> {
  bool _includeDesign = true;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: S3dTheme.mcAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.promptSheetTitle,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          Text(l.promptOfflineNote,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.promptIncludeCurrent),
            value: widget.design != null && _includeDesign,
            onChanged: widget.design == null
                ? null
                : (v) => setState(() => _includeDesign = v),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(hintText: l.promptExtraNotesHint),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.copy_all),
                  label: Text(l.promptFab),
                  onPressed: () async {
                    final svc = ref.read(promptServiceProvider);
                    final text = await svc.build(
                      lang: _normalizeLang(lang),
                      currentDesign:
                          (widget.design != null && _includeDesign)
                              ? widget.design
                              : null,
                      extraNotes: _notes.text,
                    );
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.promptCopied)),
                      );
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _normalizeLang(String code) =>
      const {'ar', 'fr', 'en'}.contains(code) ? code : 'en';
}
