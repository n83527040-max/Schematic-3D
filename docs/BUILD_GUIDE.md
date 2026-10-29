# خطوات البناء الكاملة — BUILD GUIDE

## المتطلبات

| المكون | أداة |
|---|---|
| converter | Python ≥3.11، `pip install jsonschema pytest` |
| bedrock_addon | Node ≥20 (اختبارات node:test فقط — بلا اعتماديات npm وقت التشغيل) |
| mcaddon | نفس python + `scripts/build_addon.py` |
| تطبيق Flutter | Flutter ≥3.24 (اختُبر رقميًا في CI على 3.24.5)، Android SDK 34 للـAPK |

## 1) Converter

```bash
cd converter
python -m pytest tests/ -q          # 33 passed
python -m schematic3d_converter.cli validate ../examples/tower-9x18x9.json
python -m schematic3d_converter.cli convert ../examples/tower-9x18x9.json -o /tmp/out --formats json,mcstructure
python -m schematic3d_converter.cli block-catalog --out ../app/assets/generated/block_catalog.json
```

`block-catalog` يعيد توليد لقطة الـIDs التي يستخدمها التطبيق — شغّلها بعد أي
تعديل في `converter/src/schematic3d_converter/ids.py`.

## 2) الإضافة

```bash
cd bedrock_addon && npm test                    # 29/29
node scripts/gen_tint_vectors.mjs               # يعيد tint_vectors.json (يجب ألا يتغير)
python3 ../scripts/build_addon.py --version 1.0.0
python3 ../scripts/validate_addon.py ../dist/Schematic3DBuilder.mcaddon   # RESULT: PASS
rm -rf ../dist/_base ../dist/_full              # تنظيف مؤقتات البناء
```

الخرج: `dist/Schematic3DBuilder-base.mcaddon` (فارغة) و
`dist/Schematic3DBuilder.mcaddon` (بثلاثة تصاميم مضمّنة).

## 3) التطبيق (APK)

```bash
cd app
python3 tool/sync_addon_template.py   # يزامن قوالب الإضافة إلى assets
python3 tool/gen_arb.py               # (اختياري) يعيد توليد ARB — --check للتحقق
flutter pub get && flutter gen-l10n
flutter analyze && flutter test
flutter build apk --release           # يولّد android/ تلقائيًا أول مرة (Flutter 3.24+)
```

ملاحظات إنتاجية:
- `android/` غير متتبَّع في git؛ يولّده `flutter create --platforms=android`
  (نفس ما يفعله CI) — تجنّبًا لتقادم ملفات gradle يدوية.
- minSdk: يُترك لقيمة Flutter الافتراضية (21) — يكفي file_picker/share_plus؛
  استيراد الملف إلى Minecraft يدوي كما في README.
- التطبيق **لا** يطلب إذن شبكة؛ لا INTERNET permission في المانيفست المولّد
  من قوالب Flutter الافتراضية (يُراجَع في CI analyze).

## 4) CI

`.github/workflows/ci.yml` — 4 jobs: converter pytest، addon node+build+validate،
app analyze+test+sync-checks، APK release مع upload artifacts. أي انحراف في
assets/ARBs يجعل الـjob يفشل (sync gate).

## 5) تحرير برومبت الذكاء الاصطناعي الخارجي

الملفات المصدر: `app/assets/prompts/design_prompt_ar.md` (الأصل من حزمة
المواصفة، منسوخ حرفيًا) و `design_prompt_en.md` / `_fr.md` (نفس البنية).
عدّل AR أولًا ثم ترجم — البنية موصوفة في رأس كل ملف.
