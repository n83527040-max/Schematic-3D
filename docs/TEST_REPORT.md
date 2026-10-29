# تقرير الاختبار الفعلي — TEST REPORT (2026-10-29)

بيئات الاختبار: Debian 12 (python 3.11 + node 22) داخل sandbox التطوير.
**لا يوجد Android device/emulator ولا Flutter SDK في هذه البيئة** — ما لم يُنفَّذ
فعليًا موصوف بصدق أدناه (لا ادعاء "ناجح" لأي شيء لم يُشغَّل).

## 1) Python converter — ناجح بالكامل في هذه البيئة

```
$ cd converter && python -m pytest tests/ -q
33 passed
```

تغطّي الاختبارات فعليًا:
- تحقق JSON: schema + أكواد issues (format, schemaVersion, blocks.bounds,
  blocks.paletteIndex, blocks.duplicate, dups palette merge, layers, rooms,
  volume caps…) مقابل أمثلة `examples/broken-*.json`.
- NBT قراءة/كتابة LE+BE، gzip، unwrap القوائم المغلّفة.
- فك `.mcstructure` حقيقي: `converter/tests/fixtures/forest-tower.mcstructure`
  (من ملف فانيليا فعلي) → الأبعاد (17,19,17)، 1032 بلوكًا، مطابقة البلاطة
  والحالات، وإهمال co-located مع تحذير موثّق.
- Sponge v2 `.schem` حقيقي (block-library-bridge/cabin) → خريطة Java→Bedrock
  + تقارير unsupported/dropped، و round-trip متطابق.
- Litematica + legacy `.schematic`: مسارات فكّ كاملة مع fixtures صناعية
  (بناء ملف حقيقي ببيانات معروفة والتحقق منه).
- التصدير: JSON صالح schema + `.mcstructure` مكتوب يُعاد قراءته بنفس البيانات
  (tower المُصدَّر 46818 بايت مقابل 46936 Vanilla — فارق ضغط الحقول فقط).
- CLI exit codes (0/1/2) وتقارير block-catalog.

**الأمثلة المصدّرة** (`examples/*.mcstructure`) فُحصت بمحلل مستقل وبنفس
الاختبارات: تطابق blocks كامل مع JSON.

## 2) Bedrock add-on — منطق اختُبر بلا لعبة (29/29 ناجح)

```
$ cd bedrock_addon && npm test
# tests 29 · pass 29 · fail 0
```

- `tests/planner.test.js`: بناء الطابور y→x→z، الدوران rotateXZ (nx=D-1-z)،
  Bitmap التعارض hex، tallyMaterials، chunkQueue.
- `tests/state.test.js`: تهيئة session v1، النقل/التدوير يعيدان ضبط
  التقدّم، config persistence، lang fallback.
- `tests/engine.test.js`: holopainter يفرغ الهواء فقط؛ batch build: وضع/تخطي
  (gate المخزون)، pause/resume عبر إغلاق/استئناف المولد، speed=2 للدفعة،
  stairs→ghost_wood، تقرير placed/skipped صحيح.
- `tests/tint.test.js`: 50 متجهًا ذهبيًا في `shared/tint_vectors.json`
  (يولّده `scripts/gen_tint_vectors.mjs`، regenerated اليوم: بدون فرق).
- كل API مُستخدم مُطابَق حرفيًا مع `@minecraft/server@1.26.40` و
  `@minecraft/server-ui@1.26.40` typings (تفاصيل في COMPATIBILITY.md).
- بلوكات JSON الـ13 + العنصر + الـmanifests: مُولّدة ومُتحقق من وجود
  GHOST_BLOCKS+highlight مقابلها برمجيًا داخل الـtests.

## 3) بناء وتحقق الـ.mcaddon — ناجح

```
$ python3 scripts/build_addon.py --version 1.0.0
built dist/Schematic3DBuilder-base.mcaddon
built dist/Schematic3DBuilder.mcaddon with 3 designs
$ python3 scripts/validate_addon.py dist/Schematic3DBuilder.mcaddon
... [PASS] design archbridge21x9x7: all indices in bounds
RESULT: PASS   (وكذلك PASS للمعبأ الفارغ)
```
يتحقق الفاحص من: وجود الملفين BP/RP داخل zip، صلاحيَة JSONs، تطابق UUID
الاعتمادية، `min_engine_version [1,26,40]`، أن كل تصميم مضمّن (JS +
mcstructure + فهرس manifest.json) وأن الفهارس داخل الحدود، وأن السكربتات لا
تستورد شيئًا خارج `@minecraft/server*`.

## 4) أرقام أداء (سطح مكتب، python — مرشد للتقدير فقط)

تصميم 262,144 بلوكًا (64³): export 0.09s، parse 0.40s، materials 0.13s،
JSON round-trip+validate 1.48s (10.4MB JSON / 2.1MB mcstructure)، ذروة
الذاكرة 227MB. خوارزمية الـDart port مطابقة التعقيد؛ يُعاد قياسها على الجهاز
عبر test/widgets.

## 5) تطبيق Flutter — ناجح في CI (تحقّق فعلي ✓)

البيئة هنا بلا Flutter SDK (pub.dev و storage.googleapis.com محجوبان — جُرب)،
لذلك **لم تُشغَّل اختبارات Dart محليًا؛ لا يدّعي هذا التقرير نجاحها**. ما تم:

النتائج الفعلية من CI (run 40878863727، 2026-10-29 — `completed success`):

```
flutter analyze --no-fatal-infos   → 18 issues، كلها info فقط (0 error / 0 warning)
flutter test                       → 00:08 +40: All tests passed!
flutter build apk --release        → نجاح؛ artifact بحجم 23,678,886 بايت
```

ملفات الاختبار الستة (40 اختبارًا):
- `test/domain/validation_parity_test.dart` — نفس أكواد issues الخاصة بـpytest
  على نفس fixtures الانهيار، + round-trip لموديل التصميم.
- `test/domain/tint_golden_test.dart` — 50 متجهًا ذهبيًا هي **عينها**
  `tint_vectors.json` التي تُختبر بها خوارزمية الإضافة JS → ثلاثية التطابق
  Python/JS/Dart مضمونة آليًا.
- `test/io/nbt_mcstructure_test.dart` — round-trip NBT + فك ملفات mcstructure
  حقيقية (بما فيها ملف الفانيليا forest-tower 17×19×17، وقبول قائمة-قوائم
  الفانيليا block_indices).
- `test/io/importer_test.dart` — sniff بالاحتواء لا بالامتداد، تحويل sponge2
  حقيقي (block-library-bridge) مع تقرير كل حالة palette، رفض الملفات المعطوبة
  بأكواد صحيحة، وإبلاغ format.unknown بدل الانهيار.
- `test/data/repositories_test.dart` — sqflite_common_ffi: الحفظ الثلاثي
  (أصلي+JSON+mcstructure)، بقاء الأصل عند فشل التحويل + تسجيل الفشل، فرز/بحث/
  فئات، تنظيف الحذف، والفهرسة في السجل؛ صفوف الفشل لا تلوث المكتبة (kind).
- `test/widget/app_smoke_test.dart` — إقلاع التطبيق فعليًا: EN فارغ،
  **RTL عربي** بالاتجاه الصحيح، قائمة بعد الاستيراد، شاشة الإعدادات.

أخطاء حقيقية وجدتْها CI وإُصلحت (ولهذا التحقق الآلي إلزامي هنا): ترتيب
directive للـlibrary، Endian في ByteData، خسارة بايت 0x0A الجذري بسبب قفز
"whitespace" في sniff، تغليف NbtInt للفاتSIZE/Version، قائمة-قوائم الفانيليا
في block_indices، وسادة get في دوال القفل.
- `flutter gen-l10n`: 113 مفتاحًا بمكافئة كاملة en/ar/fr؛ `gen_arb.py --check`
  يرفض أي انحراف (exit 0).

## 6) فجوات معروفة (صادقة)

| البند | الحالة | السبب / البديل |
|---|---|---|
| تشغيل APK على هاتف فعلي | ⚠️ لم يُختبر يدويًا على جهاز | APK مبني بنجاح في CI (release, 23.7MB artifact) وتجاوز اختبارات الوحدات/الودجت؛ يبقى اختبار لمس/أداء حقيقي على جهازك موصى به |
| تشغيل الإضافة داخل Minecraft فعلية | ❌ لم يُختبر على جهاز | مراجعة مصدر Construct v1.2.0 (نفس إصدار 26.40) + typings رسمية 1.26.40 + اختبارات node للمحرك؛ خطة اختبار يدوي موثقة في COMPATIBILITY.md |
| قراءة حقائب اللاعب وقت البناء | ⚠️ محدود | setBlock/runCommand مثبتة؛ فحص الجرد في الإضافة يعمل خلف gate اختياري مبني على API مقروء ومُختبَر unit-level فقط؛ إن فشل القراءة يبني ويستمر ويسجّل الإخفاق لكل بلوك (لا يُمنع البناء) |
| Custom UI panels (ScreenUI) | ⚠️ بديل | ModalForms بدلًا منها (من @minecraft/server-ui خلف مفتاح Beta APIs نفسه الذي تستخدمه الإضافة أصلًا)؛ أمر `/s3d` مخصص استُبدل ببادئة دردشة `!s3d` لأن CustomCommandRegistry لم تثبت نتيجته في حقبة 1.26.40 |
| co-located blocks (waterlogged) في mcstructure | ⚠️ تُهمل مع تحذير | الصيغة v1 = كتلة/خلية واحدة — موثق في الواجهة وفي validator |
| كتابة مباشرة لمجلدات اللعبة | 🚫 محظورة النظام | Scoped storage — تصدير مشاركة ملفات + خطوات استيراد يدوية (README + الدليل داخل التطبيق) |
| Undo / نسخ احتياطي مدمج | 🚫 خارج النطاق | قرار صريح من المواصفة (§11) |
