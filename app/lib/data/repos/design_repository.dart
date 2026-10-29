import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../../domain/model/design.dart';
import '../db/app_database.dart';

class DesignRow {
  DesignRow({
    required this.id,
    required this.name,
    required this.categoryKey,
    required this.json,
    required this.sourceFormat,
    required this.dimX,
    required this.dimY,
    required this.dimZ,
    required this.blockCount,
    required this.paletteCount,
    required this.droppedBlocks,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DesignRow.fromMap(Map<String, Object?> m) => DesignRow(
        id: (m['id'] as int),
        name: m['name'] as String,
        categoryKey: m['category_key'] as String?,
        json: m['json'] as String,
        sourceFormat: m['source_format'] as String?,
        dimX: m['dim_x'] as int,
        dimY: m['dim_y'] as int,
        dimZ: m['dim_z'] as int,
        blockCount: m['block_count'] as int,
        paletteCount: m['palette_count'] as int,
        droppedBlocks: m['dropped_blocks'] as int,
        notes: m['notes'] as String?,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );

  final int id;
  final String name;
  final String? categoryKey;
  final String json;
  final String? sourceFormat;
  final int dimX;
  final int dimY;
  final int dimZ;
  final int blockCount;
  final int paletteCount;
  final int droppedBlocks;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  int get volume => dimX * dimY * dimZ;

  Design decodeDesign() =>
      Design.fromJson(jsonDecode(json) as Map<String, Object?>);
}

class DesignQuery {
  const DesignQuery({
    this.search,
    this.categoryKey,
    this.sort = SortKey.date,
    this.descending = true,
    this.limit,
    this.offset,
  });

  final String? search;
  final String? categoryKey;
  final SortKey sort;
  final bool descending;
  final int? limit;
  final int? offset;
}

class DesignRepository {
  DesignRepository(this._db, this.storageRoot);

  final AppDatabase _db;

  /// Directory holding per-design folders with original + json + mcstructure.
  final Directory storageRoot;

  Database get db => _db.db;

  Future<Directory> designDir(int designId) async {
    final dir = Directory(p.join(storageRoot.path, 'design_$designId'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Insert design + files; returns new id. `originalBytes` may be null for
  /// in-app edits (then the JSON payload is the original record).
  Future<int> create({
    required Design design,
    required String sourceFormat,
    List<int>? originalBytes,
    List<int>? mcstructureBytes,
    String? originalFileName,
    int droppedBlocks = 0,
    String? notes,
    String? categoryKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(exportWithFormat(design));
    final id = await db.insert('designs', {
      'name': design.name,
      'category_key': categoryKey,
      'json': jsonStr,
      'source_format': sourceFormat,
      'dim_x': design.dimensions.$1,
      'dim_y': design.dimensions.$2,
      'dim_z': design.dimensions.$3,
      'block_count': design.blocks.length,
      'palette_count': design.palette.length,
      'dropped_blocks': droppedBlocks,
      'notes': notes,
      'created_at': now,
      'updated_at': now,
    });
    final dir = await designDir(id);
    final jsonPath = p.join(dir.path, '$id.json');
    await File(jsonPath).writeAsString(jsonStr);
    String? originalPath;
    if (originalBytes != null) {
      final name = (originalFileName ?? 'original_$id.$sourceFormat')
          .replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
      originalPath = p.join(dir.path, name);
      await File(originalPath).writeAsBytes(originalBytes);
    }
    String? structPath;
    if (mcstructureBytes != null) {
      structPath = p.join(dir.path, '$id.mcstructure');
      await File(structPath).writeAsBytes(mcstructureBytes);
    }
    await db.insert('design_files', {
      'design_id': id,
      'dir': dir.path,
      'original_path': originalPath,
      'json_path': jsonPath,
      'mcstructure_path': structPath,
      'size_json': File(jsonPath).lengthSync(),
      'size_mcstructure':
          structPath == null ? null : File(structPath).lengthSync(),
    });
    return id;
  }

  static Map<String, Object?> exportWithFormat(Design design) => design.toJson();

  /// Failed imports keep a raw copy of the user's original file (spec §5:
  /// failed conversion must not destroy the input). Returns the row id.
  Future<int> recordFailedImport({
    required String fileName,
    required List<int> originalBytes,
    required String format,
    required List<String> errors,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('designs', {
      'name': '[FAILED] $fileName',
      'category_key': null,
      'json': jsonEncode({
        'format': kSchematicFormat,
        'schemaVersion': kSchemaVersion,
        'name': fileName,
        'importFailed': true,
        'errors': errors,
      }),
      'source_format': format,
      'dim_x': 0, 'dim_y': 0, 'dim_z': 0,
      'block_count': 0, 'palette_count': 0,
      'dropped_blocks': 0,
      'notes': errors.join('\n'),
      'created_at': now,
      'updated_at': now,
    });
    final dir = await designDir(id);
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
    final path = p.join(dir.path, 'original_$safe');
    await File(path).writeAsBytes(originalBytes);
    await db.insert('design_files', {
      'design_id': id, 'dir': dir.path, 'original_path': path,
      'json_path': null, 'mcstructure_path': null,
    });
    return id;
  }

  Future<List<DesignRow>> query(DesignQuery q) async {
    final where = <String>[];
    final args = <Object?>[];
    if (q.search != null && q.search!.trim().isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%${q.search!.trim()}%');
    }
    if (q.categoryKey != null) {
      where.add('category_key = ?');
      args.add(q.categoryKey);
    }
    const col = {
      SortKey.name: 'name',
      SortKey.size: '(dim_x * dim_y * dim_z)',
      SortKey.blocks: 'block_count',
      SortKey.date: 'updated_at',
    };
    final finalWhere = where.isEmpty ? null : where.join(' AND ');
    final rows = await db.query(
      'designs',
      where: finalWhere,
      whereArgs: args.isEmpty ? null : args,
      orderBy: '${col[q.sort]} ${q.descending ? 'DESC' : 'ASC'}',
      limit: q.limit,
      offset: q.offset,
    );
    return rows.map(DesignRow.fromMap).toList();
  }

  Future<DesignRow?> byId(int id) async {
    final rows = await db.query('designs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return DesignRow.fromMap(rows.first);
  }

  Future<void> setCategory(int id, String? categoryKey) => db.update(
      'designs', {'category_key': categoryKey, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?', whereArgs: [id]);

  Future<void> rename(int id, String name) => db.update('designs',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?', whereArgs: [id]);

  Future<void> updateDesign(int id, Design design,
      {List<int>? mcstructureBytes}) async {
    final jsonStr = const JsonEncoder.withIndent('  ')
        .convert(exportWithFormat(design));
    await db.update(
        'designs',
        {
          'name': design.name,
          'json': jsonStr,
          'dim_x': design.dimensions.$1,
          'dim_y': design.dimensions.$2,
          'dim_z': design.dimensions.$3,
          'block_count': design.blocks.length,
          'palette_count': design.palette.length,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?', whereArgs: [id]);
    final files = await db.query('design_files',
        where: 'design_id = ?', whereArgs: [id], limit: 1);
    if (files.isNotEmpty) {
      final jsonPath = files.first['json_path'] as String;
      await File(jsonPath).writeAsString(jsonStr);
      if (mcstructureBytes != null) {
        final dir = files.first['dir'] as String;
        final structPath = p.join(dir, '$id.mcstructure');
        await File(structPath).writeAsBytes(mcstructureBytes);
        await db.update('design_files',
            {'mcstructure_path': structPath,
             'size_mcstructure': mcstructureBytes.length},
            where: 'design_id = ?', whereArgs: [id]);
      }
    }
  }

  Future<void> delete(int id) async {
    final files = await db.query('design_files',
        where: 'design_id = ?', whereArgs: [id], limit: 1);
    await db.delete('designs', where: 'id = ?', whereArgs: [id]);
    await db.delete('design_files', where: 'design_id = ?', whereArgs: [id]);
    if (files.isNotEmpty) {
      final dir = Directory(files.first['dir'] as String);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    }
  }

  Future<Map<int, (String?, String?)>> fileStates(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.generate(ids.length, (_) => '?').join(',');
    final rows = await db.rawQuery(
        'SELECT design_id, json_path, mcstructure_path FROM design_files '
        'WHERE design_id IN ($placeholders)', ids);
    return {
      for (final r in rows)
        (r['design_id'] as int): (
            r['json_path'] != null && File(r['json_path'] as String).existsSync()
                ? r['json_path'] as String
                : null,
            r['mcstructure_path'] != null &&
                    File(r['mcstructure_path'] as String).existsSync()
                ? r['mcstructure_path'] as String
                : null,
          ),
    };
  }

  Future<int> countAll() async {
    final r = await db.rawQuery('SELECT COUNT(*) c FROM designs');
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
