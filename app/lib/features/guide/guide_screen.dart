import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// How-to guide: full workflow, addon install, in-game commands, limits.
/// Long texts live in l10n (guideSteps / guideLimitations /
/// guideAddonCommands) so all three languages render the same structure.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.navGuide)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _block(
            context,
            icon: Icons.alt_route,
            title: l.guideBuildFlow,
            body: l.guideSteps,
          ),
          _block(
            context,
            icon: Icons.videogame_asset_outlined,
            title: l.guideAddonTitle,
            body: l.guideAddonCommands,
            copyable: true,
          ),
          _block(
            context,
            icon: Icons.info_outline,
            title: l.settingsAbout,
            body: l.guideLimitations,
          ),
          const SizedBox(height: 8),
          Text(l.promptOfflineNote,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: S3dTheme.mcAmber)),
        ],
      ),
    );
  }

  Widget _block(BuildContext context,
      {required IconData icon,
      required String title,
      required String body,
      bool copyable = false}) {
    final l = l10n(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: S3dTheme.mcLime, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (copyable)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: l.copy,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: body));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.copied)));
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(body,
                style: const TextStyle(height: 1.6, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}
