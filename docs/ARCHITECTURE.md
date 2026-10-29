# البنية — Architecture

## تدفق البيانات (من الملف إلى البلوك في اللعبة)

```
ملف المستخدم (json/mcstructure/schem/schematic)
  │  DesignImporter.sniff (محتوى لا امتداد)      app/lib/domain/formats/
  ▼
parse: McstructureCodec | LitematicCodecs(sponge2/litematic) | legacy
  │  Mapper: java→bedrock palette + notes        (يتطابق مع converter/src/.../mapping.py)
  ▼
validateSchematicDoc ── أكواد issues مطابقة لـ Python (pytest goldens)
  │
  ├─▶ SQLite: designs + design_files (الأصلي + JSON + mcstructure) + folders + import_log
  ├─▶ VoxelMeshBuilder (culling + painter) و FloorPlan (شرائح/غرف)
  ├─▶ McstructureCodec.encode → .mcstructure
  └─▶ AddonPacker → .mcaddon (نفس مخطط build_addon.py:
        scripts/s3d/data/<id>.js + manifest.json + index.js + structures/s3d/<id>.mcstructure)
             ▼
      داخل اللعبة: data/index.js → planner (y→x→z، rotateXZ) → holo (ghost paint)
                   → build.js (runJob batches، gate جرد اختياري، تقرير لكل بلوك)
```

## الطبقات داخل التطبيق

- `lib/domain/` نقي بلا Flutter widget dependencies قدر الإمكان (يُختبر على
  VM): model, validation, nbt, formats (mcstructure/litematic/mapper/catalog),
  render3d (voxel_mesh/floor_plan), materials, prompt.
- `lib/data/`: sqflite v1 (3 جداول + فهرسان)، folders seed من المواصفة،
  ImportService (الأصلي يُحفظ دائمًا أولًا — acceptance criterion)،
  FileIoService (SAF picker / share sheet فقط — لا كتابة لمجلدات اللعبة)،
  AppSettings (shared_preferences).
- `lib/features/`: library (بحث/فرز/فئات/تحديد متعدد للتصدير مجمّعًا)،
  detail (3D/مخطط طوابق/طبقات/غرف/مواد/معلومات + إعادة تسمية/نقل/حذف + 3
  تصديرات)، import (تقرير كامل: errors/warnings/unsupported)، log، guide،
  settings، prompt sheet (نسخ الحافظة فقط).
- `lib/app/`: bootstrap (فتح DB، تحميل block_catalog، overrides للـRiverpod).

## قرارات تصميم

- **لا AI ولا شبكة**: PromptService يبني نص البرومبت (أصل AR في
  `assets/prompts/`، مع FR/EN منسوخين بنيويًا) ويضيف JSON التصميم الحالي
  اختياريًا؛ النسخ عبر Clipboard فقط.
- **تطابق ثلاثي**: أكواد الـvalidator، tint vectors، وأكواد sniff/parse نفسها
  تُختبر بثلاث لغات تنفيذ (Python، JS للإضافة، Dart للتطبيق) على نفس
  الملفات في `examples/` و `assets/generated/tint_vectors.json`.
- **RTL/L10n**: ARB واحد المصدر (tool/gen_arb.py) — 113 مفتاحًا بمكافئة
  مفروضة؛ MaterialApp يختار اللغة (system/ar/fr/en) وRTL تلقائي.
- **حجم العرض**: mesh مبني من مصفوفات Flat (Float32List) بحد أقصى 300k quad
  مع إحصاءات (quads/culled/ms) ظاهرة في الـHUD — لا widgets لكل بلوك.
- **الإضافة**: `!s3d` chat prefix (cancel=true) بدل CustomCommandRegistry؛
  عنصر `s3d:menu` يعطي/يستخدم لفتح القائمة؛
  الجلسة والإعدادات (`state.js`) تعيش في ذاكرة العالم لكل جلسة تشغيل — لا
  dynamic properties ولا ملفات (لا حاجة للتراجع عن شيء بين الجلسات؛ البناء
  نفسه دائم في العالم).
