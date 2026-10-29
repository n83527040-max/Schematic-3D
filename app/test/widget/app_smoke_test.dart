import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:schematic_3d/app/app.dart';
import 'package:schematic_3d/app/providers.dart';
import 'package:schematic_3d/data/db/app_database.dart';
import 'package:schematic_3d/data/repos/design_repository.dart';
import 'package:schematic_3d/data/settings/app_settings.dart';
import 'package:schematic_3d/domain/validation/design_validator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

/// End-to-end wiring WITHOUT the asset bundle: DB + repos + screens.
void main() {
  late Directory tmp;
  late AppDatabase db;
  late AppSettings settings;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('s3d_ui_');
    db = await AppDatabase.open(p.join(tmp.path, 'test.db'));
    settings = await AppSettings.load();
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget app(String lang) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          storageRootProvider.overrideWithValue(tmp),
        ],
        child: S3dApp(languageOverride: lang),
      );

  testWidgets('library renders empty state in English', (tester) async {
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    expect(find.text('Schematic 3D'), findsOneWidget);
    expect(find.text('No designs yet'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget); // prompt FAB
    expect(find.text('Import'), findsWidgets);
  });

  testWidgets('Arabic renders RTL and localized labels', (tester) async {
    await tester.pumpWidget(app('ar'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('مخطط ثلاثي الأبعاد'));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('لا توجد تصاميم بعد'), findsOneWidget);
  });

  testWidgets('library lists an imported design after refresh',
      (tester) async {
    // seed the DB the same way the import pipeline does
    final doc = readJsonFixture('examples/tower-9x18x9.json');
    // build via repo directly (importer needs catalog asset in app flow;
    // the design JSON here is already bedrock-mapped examples content)
    final repo = DesignRepository(db, tmp);
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.text('Schematic 3D')));
    final report = validateSchematicDoc(doc);
    expect(report.report.ok, isTrue);
    await repo.create(
        design: report.design!, sourceFormat: 'schematic3dJson');
    await container.read(libraryProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('Tower'), findsWidgets);
  });

  testWidgets('settings: language switch chips visible', (tester) async {
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.textContaining('Always required'), findsOneWidget);
  });
}
