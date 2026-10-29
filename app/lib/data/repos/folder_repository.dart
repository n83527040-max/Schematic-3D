import '../../core/constants.dart';
import '../db/app_database.dart';

class FolderRow {
  FolderRow({
    required this.key,
    required this.labelAr,
    this.labelFr,
    this.labelEn,
    this.emoji,
    this.parentKey,
    required this.custom,
    required this.sort,
  });

  factory FolderRow.fromMap(Map<String, Object?> m) => FolderRow(
        key: m['key'] as String,
        labelAr: m['label_ar'] as String,
        labelFr: m['label_fr'] as String?,
        labelEn: m['label_en'] as String?,
        emoji: m['emoji'] as String?,
        parentKey: m['parent_key'] as String?,
        custom: (m['custom'] as int) == 1,
        sort: m['sort'] as int,
      );

  final String key;
  final String labelAr;
  final String? labelFr;
  final String? labelEn;
  final String? emoji;
  final String? parentKey;
  final bool custom;
  final int sort;

  String label(String locale) {
    if (locale.startsWith('ar')) return labelAr;
    if (locale.startsWith('fr')) return labelFr ?? labelEn ?? labelAr;
    return labelEn ?? labelAr;
  }
}

/// Categories/folders. The 8 spec categories are seeded and non-deletable;
/// users can add custom folders (parentKey null = top level).
class FolderRepository {
  FolderRepository(this._db);
  final AppDatabase _db;

  Future<List<FolderRow>> all() async {
    final rows = await _db.db.query('folders', orderBy: 'sort ASC');
    return rows.map(FolderRow.fromMap).toList();
  }

  Future<int> addCustom(String arLabel, String frLabel, String enLabel) async {
    final key = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    await _db.db.insert('folders', {
      'key': key,
      'label_ar': arLabel,
      'label_fr': frLabel,
      'label_en': enLabel,
      'emoji': '📁',
      'custom': 1,
      'sort': kCategoryKeys.length + 100,
    });
    return key.hashCode & 0x7FFFFFFF;
  }

  Future<void> removeCustom(String key) => _db.db
      .delete('folders', where: 'key = ? AND custom = 1', whereArgs: [key]);

  /// Number of designs per category (for the badges).
  Future<Map<String, int>> counts() async {
    final rows = await _db.db.rawQuery(
        'SELECT category_key k, COUNT(*) c FROM designs '
        'WHERE category_key IS NOT NULL GROUP BY category_key');
    return {
      for (final r in rows) r['k'] as String: r['c'] as int,
    };
  }
}
