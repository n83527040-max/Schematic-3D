import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/guide/guide_screen.dart';
import '../features/importer/import_screen.dart';
import '../features/library/library_screen.dart';
import '../features/log/log_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/theme/theme.dart';
import '../l10n/generated/app_localizations.dart';

class S3dApp extends StatelessWidget {
  const S3dApp({super.key, this.languageOverride = ''});

  /// '' → follow system (spec: AR RTL / FR / EN)
  final String languageOverride;

  static final _locales = {
    'ar': const Locale('ar'),
    'fr': const Locale('fr'),
    'en': const Locale('en'),
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Schematic 3D',
      debugShowCheckedModeBanner: false,
      theme: S3dTheme.dark(),
      locale: languageOverride.isEmpty
          ? null
          : _locales[languageOverride] ?? const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          LibraryScreen(),
          ImportScreen(),
          GuideScreen(),
          LogScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard),
              label: l.navLibrary),
          NavigationDestination(
              icon: const Icon(Icons.file_download_outlined),
              selectedIcon: const Icon(Icons.file_download),
              label: l.navImport),
          NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: l.navGuide),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: l.navLog),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: l.navSettings),
        ],
      ),
    );
  }
}
