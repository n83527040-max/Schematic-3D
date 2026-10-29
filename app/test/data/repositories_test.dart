import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:schematic_3d/core/constants.dart';
import 'package:schematic_3d/data/db/app_database.dart';
import 'package:schematic_3d/data/repos/design_repository.dart';
import 'package:schematic_3d/data/repos/folder_repository.dart';
import 'package:schematic_3d/data/repos/import_log_repository.dart';
import 'package:schematic_3d/data/services/import_service.dart';
import 'package:schematic_3d/domain/formats/block_catalog.dart';
import 'package:schematic_3d/domain/formats/design_importer.dart';
import 'package:schematic_3d/domain/model/design.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final raw = File(fixture('app/assets/generated/block_catalog.json'))
        .readAsStringSync();
    final doc = jsonDecode(raw) as Map<String, Object?>;
    BlockCatalog.loadFromData(
      known: {
        for (final id in (doc['knownBedrockIds'] as List)) 'minecraft:$id',
      },
      javaToBedrock: {
        for (final e in (doc['javaToBedrock'] as Map).entries)
          e.key.toString(): e.value.toString(),
      },
      javaFamily: {
        for (final e in (doc['javaFamilyToBedrock'] as Map).entries)
          e.key.toString(): {
            for (final q in (e.value as Map).entries)
              q.key.toString(): q.value.toString(),
          },
      },
    );
  });

  late Directory tmp;
  late AppDatabase db;
  late Directory storage;
  late DesignRepository designs;
  late ImportLogRepository log;
  late FolderRepository folders;
  late ImportService importer;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('s3d_test_');
    db = await AppDatabase.open(p.join(tmp.path, 'test.db'));
    storage = Directory(p.join(tmp.path, 'designs'))..createSync();
    designs = DesignRepository(db, storage);
    log = ImportLogRepository(db);
    folders = FolderRepository(db);
    importer = ImportService(
      importer: DesignImporter(),
      designs: designs,
      log: log,
      storageRoot: storage,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('folders seeded with the 8 spec categories', () async {
    final all = await folders.all();
    expect(all.length, 8);
    expect(all.map((f) => f.key),
        containsAll(<String>['palaces', 'houses', 'towers', 'bridges',
          'farms', 'decor', 'industrial', 'other']));
    final ar = all.firstWhere((f) => f.key == 'towers');
    expect(ar.label('ar'), 'أبراج');
    expect(ar.label('fr'), 'Tours');
    expect(ar.label('en'), 'Towers');
  });

  test('valid import stores files: original + json + mcstructure', () async {
    final bytes = Uint8List.fromList(
        File(fixture('examples/tower-9x18x9.json')).readAsBytesSync());
    final outcome = await importer.importFromBytes(bytes, 'tower-9x18x9.json');
    expect(outcome.ok, isTrue, reason: outcome.report.issues.toString());

    final rows = await designs.query(const DesignQuery());
    expect(rows.length, 1);
    final row = rows.single;
    expect(row.name, contains('Tower'));
    expect(row.categoryKey, 'towers'); // guessed from name keyword

    final files = await designs.fileStates([row.id]);
    final (jsonPath, structPath) = files[row.id]!;
    expect(jsonPath, isNotNull);
    expect(structPath, isNotNull);
    expect(File(jsonPath!).existsSync(), isTrue);
    expect(File(structPath!).existsSync(), isTrue);
    final dir = Directory(p.join(storage.path, 'design_${row.id}'));
    final originals =
        dir.listSync().whereType<File>().where((f) => !p.basename(f.path).startsWith('${row.id}.')).toList();
    expect(originals.map((f) => p.basename(f.path)),
        contains('tower-9x18x9.json')); // original kept

    final logged = await log.recent();
    expect(logged.single.status, ImportStatus.success);
    expect(logged.single.designId, row.id);
  });

  test('failed import keeps the original file and logs the failure',
      () async {
    final garbage = Uint8List.fromList(
        File(fixture('examples/broken-truncated.json')).readAsBytesSync());
    final outcome =
        await importer.importFromBytes(garbage, 'broken-truncated.json');
    expect(outcome.ok, isFalse);

    final rows = await designs.query(const DesignQuery());
    expect(rows, isEmpty); // failed rows are not library entries

    final logged = await log.recent();
    expect(logged.single.status, ImportStatus.failed);
    expect(logged.single.errorCount, greaterThan(0));

    // ORIGINAL persisted under design_files even on failure
    final id = logged.single.designId!;
    final dir = Directory(p.join(storage.path, 'design_$id'));
    expect(dir.existsSync(), isTrue);
    final kept = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).contains('broken-truncated'))
        .toList();
    expect(kept.length, 1);
    expect(kept.single.readAsBytesSync(), garbage);
  });

  test('query: search + category + sort by blocks desc', () async {
    Future<void> add(String name, int blocks, String? cat) async {
      final design = Design(
        name: name,
        dimensions: (blocks > 2 ? 4 : 2, 1, 2),
        palette: const [PaletteEntry('minecraft:stone')],
        blocks: [
          for (var i = 0; i < blocks; i++)
            BlockEntry(i % 4, 0, (i ~/ 4) % 2, 0),
        ],
        layers: const [],
      );
      await designs.create(
          design: design, sourceFormat: 'json', categoryKey: cat);
    }

    await add('Alpha house', 3, 'houses');
    await add('Beta tower', 8, 'towers');
    await add('Gamma', 5, null);

    final byBlocks =
        await designs.query(const DesignQuery(sort: SortKey.blocks));
    expect(byBlocks.map((r) => r.name).toList(),
        ['Beta tower', 'Gamma', 'Alpha house']);

    final houses = await designs
        .query(const DesignQuery(categoryKey: 'houses'));
    expect(houses.single.name, 'Alpha house');

    final searched =
        await designs.query(const DesignQuery(search: 'eta'));
    expect(searched.single.name, 'Beta tower');
  });

  test('rename + move + delete cleans up files', () async {
    final bytes = Uint8List.fromList(
        File(fixture('examples/cottage-12x8x12.json')).readAsBytesSync());
    final outcome =
        await importer.importFromBytes(bytes, 'cottage-12x8x12.json');
    final id = (await designs.query(const DesignQuery())).single.id;
    await designs.rename(id, 'Cottage renamed');
    await designs.setCategory(id, 'palaces');
    var row = (await designs.byId(id))!;
    expect(row.name, 'Cottage renamed');
    expect(row.categoryKey, 'palaces');
    expect(outcome.ok, isTrue);
    final dirPath = p.join(storage.path, 'design_$id');
    expect(Directory(dirPath).existsSync(), isTrue);
    await designs.delete(id);
    expect(await designs.byId(id), isNull);
    expect(Directory(dirPath).existsSync(), isFalse);
  });

  test('import log: unsupported blocks recorded and listable', () async {
    await log.log(
      fileName: 'x.json',
      status: ImportStatus.partial,
      errorCount: 0,
      warningCount: 2,
      droppedBlocks: 7,
      unsupportedBlocks: const ['minecraft:big_dripleaf', 'chisel:marble2'],
    );
    final rows = await log.recent();
    expect(rows.single.unsupportedBlocks.length, 2);
    expect(rows.single.droppedBlocks, 7);
    expect(await log.clear(), 1);
    expect(await log.recent(), isEmpty);
  });
}

// model imports at bottom for brevity
// ignore: depend_on_referenced_packages
// (flutter_test re-exports needed types)
