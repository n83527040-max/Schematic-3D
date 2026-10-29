import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';

/// Local SQLite store: designs (JSON payload + stats), folders (spec
/// categories tree) and the import log. All data stays on-device.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static Future<AppDatabase> open(String path) async {
    final db = await openDatabase(
      path,
      version: kDatabaseVersion,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE folders(
            key TEXT PRIMARY KEY,
            label_ar TEXT NOT NULL,
            label_fr TEXT,
            label_en TEXT,
            emoji TEXT,
            parent_key TEXT,
            custom INTEGER NOT NULL DEFAULT 0,
            sort INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE designs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category_key TEXT,
            json TEXT NOT NULL,
            source_format TEXT,
            dim_x INTEGER NOT NULL,
            dim_y INTEGER NOT NULL,
            dim_z INTEGER NOT NULL,
            block_count INTEGER NOT NULL,
            palette_count INTEGER NOT NULL,
            dropped_blocks INTEGER NOT NULL DEFAULT 0,
            notes TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_designs_category ON designs(category_key)');
        await db.execute('CREATE INDEX idx_designs_updated ON designs(updated_at)');
        await db.execute('''
          CREATE TABLE design_files(
            design_id INTEGER PRIMARY KEY,
            dir TEXT NOT NULL,
            original_path TEXT,
            json_path TEXT,
            mcstructure_path TEXT,
            size_json INTEGER,
            size_mcstructure INTEGER
          )''');
        await db.execute('''
          CREATE TABLE import_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_name TEXT NOT NULL,
            status TEXT NOT NULL,
            design_id INTEGER,
            source_format TEXT,
            error_count INTEGER NOT NULL DEFAULT 0,
            warning_count INTEGER NOT NULL DEFAULT 0,
            dropped_blocks INTEGER NOT NULL DEFAULT 0,
            unsupported_blocks TEXT,
            message TEXT,
            created_at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_log_created ON import_log(created_at)');
        await _seedFolders(db);
      },
    );
    return AppDatabase._(db);
  }

  static const folderLabels = <(String, String, String, String, String)>[
    // key, ar, fr, en, emoji
    ('palaces', 'قصور', 'Palais', 'Palaces', '🏛️'),
    ('houses', 'منازل', 'Maisons', 'Houses', '🏠'),
    ('towers', 'أبراج', 'Tours', 'Towers', '🗼'),
    ('bridges', 'جسور', 'Ponts', 'Bridges', '🌉'),
    ('farms', 'مزارع', 'Fermes', 'Farms', '🌾'),
    ('decor', 'ديكورات', 'Décorations', 'Decor', '🪴'),
    ('industrial', 'صناعي', 'Industriel', 'Industrial', '⚙️'),
    ('other', 'أخرى', 'Autre', 'Other', '📦'),
  ];

  static Future<void> _seedFolders(Database db) async {
    var i = 0;
    for (final f in folderLabels) {
      await db.insert('folders', {
        'key': f.$1, 'label_ar': f.$2, 'label_fr': f.$3, 'label_en': f.$4,
        'emoji': f.$5, 'custom': 0, 'sort': i++,
      });
    }
  }

  Future<void> close() => db.close();
}
