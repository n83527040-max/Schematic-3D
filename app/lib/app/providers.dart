import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../data/db/app_database.dart';
import '../data/repos/design_repository.dart';
import '../data/repos/folder_repository.dart';
import '../data/repos/import_log_repository.dart';
import '../data/services/addon_packer.dart';
import '../data/services/file_io_service.dart';
import '../data/services/import_service.dart';
import '../data/settings/app_settings.dart';
import '../domain/formats/design_importer.dart';
import '../domain/prompt/prompt_service.dart';

/// Overridden in main() after bootstrap.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden');
});

final settingsProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('settingsProvider must be overridden');
});

final storageRootProvider = Provider<Directory>((ref) {
  throw UnimplementedError('storageRootProvider must be overridden');
});

final designRepoProvider = Provider<DesignRepository>((ref) =>
    DesignRepository(ref.watch(databaseProvider), ref.watch(storageRootProvider)));

final folderRepoProvider = Provider<FolderRepository>(
    (ref) => FolderRepository(ref.watch(databaseProvider)));

final importLogRepoProvider = Provider<ImportLogRepository>(
    (ref) => ImportLogRepository(ref.watch(databaseProvider)));

final importLogProvider = FutureProvider<List<ImportLogEntry>>(
    (ref) => ref.watch(importLogRepoProvider).recent());

final fileIoProvider = Provider<FileIoService>((_) => const FileIoService());

final addonPackerProvider = Provider<AddonPacker>((_) => const AddonPacker());

final importerProvider = Provider<DesignImporter>((_) => DesignImporter());

final importServiceProvider = Provider<ImportService>((ref) => ImportService(
      importer: ref.watch(importerProvider),
      designs: ref.watch(designRepoProvider),
      log: ref.watch(importLogRepoProvider),
      storageRoot: ref.watch(storageRootProvider),
    ));

/// Template asset layout: assets/prompts/design_prompt_{lang}.md
final promptServiceProvider = Provider<PromptService>((ref) => PromptService(
      loadTemplate: (lang) =>
          rootBundle.loadString('${kPromptAssetPath}_$lang.md'),
    ));

// ---------------------------------------------------------------- library --

class LibraryState {
  const LibraryState({
    required this.rows,
    required this.loading,
    this.error,
    this.selected = const {},
  });

  final List<DesignRow> rows;
  final bool loading;
  final String? error;
  final Set<int> selected;

  LibraryState copyWith({
    List<DesignRow>? rows,
    bool? loading,
    String? error,
    Set<int>? selected,
  }) =>
      LibraryState(
        rows: rows ?? this.rows,
        loading: loading ?? this.loading,
        error: error,
        selected: selected ?? this.selected,
      );
}

class LibraryController extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    refresh();
    return const LibraryState(rows: [], loading: true);
  }

  String? _search;
  String? _category;

  String? get category => _category;

  Future<void> refresh() async {
    final settings = ref.read(settingsProvider);
    final q = DesignQuery(
      search: _search,
      categoryKey: _category,
      sort: settings.sortKey,
      descending: settings.sortDescending,
    );
    try {
      final rows = await ref.read(designRepoProvider).query(q);
      state = state.copyWith(rows: rows, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setSearch(String? v) {
    _search = v;
    refresh();
  }

  void setCategory(String? v) {
    _category = v;
    refresh();
  }

  void toggleSelect(int id) {
    final sel = {...state.selected};
    if (!sel.remove(id)) sel.add(id);
    state = state.copyWith(selected: sel);
  }

  void clearSelection() => state = state.copyWith(selected: const {});
}

final libraryProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

// ----------------------------------------------------------------- files --

/// Export directory shared by share/save flows (app-scoped).
Future<Directory> exportsDir() async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(root.path, 'exports'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

// ------------------------------------------------------------- bootstrap --

class AppBootstrap {
  AppBootstrap(this.db, this.settings, this.root);
  final AppDatabase db;
  final AppSettings settings;
  final Directory root;

  static Future<AppBootstrap> init() async {
    final root = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(root.path, 'data'))
      ..createSync(recursive: true);
    final db = await AppDatabase.open(p.join(dbDir.path, kDatabaseName));
    final settings = await AppSettings.load();
    return AppBootstrap(db, settings, root);
  }

  List<Override> get overrides => [
        databaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        storageRootProvider.overrideWithValue(Directory(
            p.join(root.path, 'designs'))..createSync(recursive: true)),
      ];
}
