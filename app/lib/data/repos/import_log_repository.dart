import 'dart:convert';

import '../db/app_database.dart';

enum ImportStatus { success, partial, failed }

class ImportLogEntry {
  ImportLogEntry({
    required this.id,
    required this.fileName,
    required this.status,
    this.designId,
    this.sourceFormat,
    required this.errorCount,
    required this.warningCount,
    required this.droppedBlocks,
    this.unsupportedBlocks = const [],
    this.message,
    required this.createdAt,
  });

  factory ImportLogEntry.fromMap(Map<String, Object?> m) => ImportLogEntry(
        id: m['id'] as int,
        fileName: m['file_name'] as String,
        status: ImportStatus.values.firstWhere(
            (s) => s.name == m['status'], orElse: () => ImportStatus.failed),
        designId: m['design_id'] as int?,
        sourceFormat: m['source_format'] as String?,
        errorCount: m['error_count'] as int,
        warningCount: m['warning_count'] as int,
        droppedBlocks: m['dropped_blocks'] as int,
        unsupportedBlocks: m['unsupported_blocks'] == null
            ? const []
            : (jsonDecode(m['unsupported_blocks'] as String) as List)
                .cast<String>(),
        message: m['message'] as String?,
        createdAt: m['created_at'] as int,
      );

  final int id;
  final String fileName;
  final ImportStatus status;
  final int? designId;
  final String? sourceFormat;
  final int errorCount;
  final int warningCount;
  final int droppedBlocks;
  final List<String> unsupportedBlocks;
  final String? message;
  final int createdAt;
}

/// Import/convert log (spec §5): every attempt recorded with outcome and the
/// list of unsupported blocks when anything was dropped.
class ImportLogRepository {
  ImportLogRepository(this._db);
  final AppDatabase _db;

  Future<void> log({
    required String fileName,
    required ImportStatus status,
    int? designId,
    String? sourceFormat,
    int errorCount = 0,
    int warningCount = 0,
    int droppedBlocks = 0,
    List<String> unsupportedBlocks = const [],
    String? message,
  }) async {
    await _db.db.insert('import_log', {
      'file_name': fileName,
      'status': status.name,
      'design_id': designId,
      'source_format': sourceFormat,
      'error_count': errorCount,
      'warning_count': warningCount,
      'dropped_blocks': droppedBlocks,
      'unsupported_blocks':
          unsupportedBlocks.isEmpty ? null : jsonEncode(unsupportedBlocks),
      'message': message,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ImportLogEntry>> recent({int limit = 200}) async {
    final rows = await _db.db.query('import_log',
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(ImportLogEntry.fromMap).toList();
  }

  Future<int> clear() => _db.db.delete('import_log');
}
