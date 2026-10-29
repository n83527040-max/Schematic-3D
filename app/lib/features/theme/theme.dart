import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// Identity: NOVA × Minecraft — deep space navy base, emerald/lime build
/// accents, amber highlights, translucent glass cards.
class S3dTheme {
  S3dTheme._();

  static const novaDeep = Color(0xFF0B1020);
  static const novaPanel = Color(0xFF141B33);
  static const novaLine = Color(0xFF24304F);
  static const mcGrass = Color(0xFF509B41);
  static const mcLime = Color(0xFF8BE04E);
  static const mcAmber = Color(0xFFFADC78);
  static const mcSky = Color(0xFF80D8FF);
  static const danger = Color(0xFFE05252);

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: mcLime,
        onPrimary: Color(0xFF08210A),
        secondary: mcAmber,
        onSecondary: Color(0xFF2A2000),
        surface: novaPanel,
        onSurface: Color(0xFFE8ECF8),
        error: danger,
      ),
      scaffoldBackgroundColor: novaDeep,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: novaDeep,
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: novaPanel,
        indicatorColor: mcLime.withOpacity(0.22),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: base.colorScheme.onSurface.withOpacity(0.9)),
        ),
      ),
      cardTheme: CardTheme(
        color: novaPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: novaLine),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: novaPanel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: novaLine),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: novaPanel,
        side: const BorderSide(color: novaLine),
      ),
      dividerTheme: const DividerThemeData(color: novaLine, thickness: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: mcGrass,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: mcAmber,
        foregroundColor: Color(0xFF2A2000),
        shape: CircleBorder(),
      ),
    );
  }
}

/// UI text convention: l10n(context).someKey
AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  TextDirection get dir => Directionality.of(this);
}
