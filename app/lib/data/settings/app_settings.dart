import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';

/// Persisted app settings (language, default view mode, sort, category,
/// batch speed, confirm-before-build always ON — not configurable).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  // ---- language override ('' = system) ---------------------------------
  String get languageOverride => _prefs.getString('lang') ?? '';
  set languageOverride(String v) {
    if (v.isEmpty) {
      _prefs.remove('lang');
    } else {
      _prefs.setString('lang', v);
    }
    notifyListeners();
  }

  // ---- default view mode --------------------------------------------------
  ViewMode get defaultViewMode {
    final v = _prefs.getString('view_mode');
    return v == 'plan' ? ViewMode.floorPlan : ViewMode.threeD;
  }

  set defaultViewMode(ViewMode m) {
    _prefs.setString('view_mode', m == ViewMode.floorPlan ? 'plan' : '3d');
    notifyListeners();
  }

  // ---- library sort -------------------------------------------------------
  SortKey get sortKey {
    final i = _prefs.getInt('sort_key') ?? 3;
    return SortKey.values[i.clamp(0, SortKey.values.length - 1)];
  }

  set sortKey(SortKey k) {
    _prefs.setInt('sort_key', k.index);
    notifyListeners();
  }

  bool get sortDescending => _prefs.getBool('sort_desc') ?? true;
  set sortDescending(bool v) {
    _prefs.setBool('sort_desc', v);
    notifyListeners();
  }

  // ---- batch build default speed (blocks per tick chunk; in-game slider
  // overrides per session — the add-on owns the actual value) -------------
  int get batchSpeed => (_prefs.getInt('batch_speed') ?? 32).clamp(1, 256);
  set batchSpeed(int v) {
    _prefs.setInt('batch_speed', v);
    notifyListeners();
  }

  // ---- grid density for floor plan ---------------------------------------
  double get planCellScale => (_prefs.getDouble('plan_scale') ?? 14.0).clamp(4, 48);
  set planCellScale(double v) {
    _prefs.setDouble('plan_scale', v);
    notifyListeners();
  }

  // ---- "show first-run guide" dismissal -----------------------------------
  bool get guideSeen => _prefs.getBool('guide_seen') ?? false;
  set guideSeen(bool v) {
    _prefs.setBool('guide_seen', v);
    notifyListeners();
  }

  // ---- confirm-before-build is a safety invariant, exposed read-only ------
  bool get confirmBeforeBuild => true;
}
