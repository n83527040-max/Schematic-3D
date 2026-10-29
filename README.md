# Schematic 3D — مكتبة تصاميم ماينكرافت ثلاثية الأبعاد

تطبيق Flutter للأندرويد + إضافة Minecraft Bedrock باسم **Schematic 3D Builder**
(مستهدف: Bedrock 26.40.5 للأندرويد). يعمل بالكامل دون إنترنت، ولا يحتوي على أي
ذكاء اصطناعي مدمج: الزر الدائري ينسخ برومبت جاهزًا إلى الحافظة لاستخدامه في
الأداة الخارجية التي تختارها.

**Schematic 3D** — an Android Flutter app + a Minecraft Bedrock add-on
(**Schematic 3D Builder**, targeting Bedrock 26.40.5). 100% offline, no built-in
AI: the round button only copies an external-AI prompt template to the clipboard.

## المكونات / Components

| المسار | الوصف |
|---|---|
| `app/` | تطبيق Flutter — مكتبة التصاميم، الاستيراد والتحويل، معاينة 3D ومخطط الطوابق، المواد، السجل، الإعدادات، الدليل (AR/FR/EN، دعم RTL) |
| `bedrock_addon/` | مصدر الإضافة (BP + RP): قوائم تصاميم، هولوغرام، تحريك/تدوير/ارتفاع، طبقات وغرف، بناء يدوي موجه، بناء جماعي مع سرعة/إيقاف/استئناف، فحص تعارض + تأكيد إلزامي قبل البناء |
| `converter/` | محلر Python حقيقي: `.mcstructure` / Sponge v2 `.schem` / Litematica / legacy + مخطط Java→Bedrock + مصدر JSON الصالح — 33 اختبار pytest ناجح |
| `scripts/` | بناء `.mcaddon` (نسخة فارغة + نسخة بالتصاميم) والتحقق البنيوي منه |
| `examples/` | 3 تصاميم صالحة (JSON + mcstructure) و5 ملفات معطوبة لاختبارات الرفض |
| `docs/` | تقارير الاختبار والتوافق والبنية وخطوات البناء |
| `dist/` | ناتج `.mcaddon` المبني والمُتحقق منه |

## نتائج الاختبارات الحالية (في بيئة التطوير، بدون جهاز)

| الحزمة | النتيجة |
|---|---|
| `converter` pytest | **33/33 ناجح** بما فيها تحويل ملفات حقيقية (برج الغابة 17×19×17 / 1032 بلوكًا) وتطابق round-trip |
| `bedrock_addon` node --test | **29/29 ناجح** (planner/state/engine/tint) |
| validate_addon للـ mcaddon | **PASS** للمعبأ وغير المعبأ (UUIDs، تبعيات 2.10.0-beta، 3 تصميمات مضمّنة) |
| اختبارات Dart للتطبيق | **40/40 ناجحة في CI** + `flutter analyze` بلا أخطاء + **بناء APK release ناجح** (artifact في آخر CI run) — انظر docs/TEST_REPORT.md |
| تشغيل داخل Minecraft على جهاز | غير مُختبَر على جهاز فعلي هنا — التحقق تم بمراجعة كود Construct v1.2.0 و typings رسمية 1.26.40؛ التفاصيل في docs/COMPATIBILITY.md |

## البناء / Build

## الحصول على الناتجين الجاهزين

- **APK**: من تبويب Actions → آخر CI run ناجح → artifact باسم `apk-release`
  (app-release.apk). أو ابنِه محليًا بالأدوات أدناه.
- **MCAddon**: artifact باسم `mcaddon` (ملفا base + full)، أو `dist/` في المستودع.

```bash
# المحولر + الاختبارات
cd converter && pip install jsonschema pytest && python -m pytest tests/ -q

# الإضافة: اختبارات + بناء mcaddon
cd bedrock_addon && npm test
python3 scripts/build_addon.py --version 1.0.0
python3 scripts/validate_addon.py dist/Schematic3DBuilder.mcaddon

# التطبيق (يتطلب Flutter ≥3.24 — يُبنى تلقائيًا في CI مع APK)
cd app && flutter pub get && flutter gen-l10n && flutter analyze && flutter test
flutter build apk --release   # يولّد android/ عبر CI إن غاب
```

أو شغّل CI بالكامل: كل ما فوق يُنفَّذ في `.github/workflows/ci.yml` ويرفع
الـAPK والـ mcaddon كـ artifacts.

## استيراد الإضافة إلى Minecraft (خطوات يدوية موثقة)

قيود تخزين Android المقيّد (scoped storage) تمنع الكتابة مباشرة إلى مجلدات
لعبة Minecraft، لذلك:

1. من التطبيق: افتح التصميم → تصدير → «تصدير كحزمة MCAddon» ثم شارك الملف
   `*.mcaddon`.
2. اختر فتحه بـ **Minecraft** (يستورد الحزمتين تلقائيًا)، أو انسخه يدويًا إلى
   `games/com.mojang/behavior_packs` و `resource_packs`.
3. فعّل **Behavior** و **Resource** pack في إعدادات العالم، وفعّل **Beta API
   Modules** (المجموعة تستخدم Script API 2.0.0/β-2.10).
4. داخل اللعب: استخدم عنصر القائمة `S3D Menu` أو أوامر الدردشة `!s3d ...`
   (القائمة الكاملة في تبويب الدليل داخل التطبيق).

تصدير `.mcstructure` الفردي متاح أيضًا لأي أداة مفضلة لديك.

## قواعد منتِجة مُطبَّقة (من المواصفة)

- الملف الأصلي لا يضيع أبدًا عند فشل التحويل: يُحفظ في تخزين التطبيق ويسجَّل في السجل.
- البلوكات غير المدعومة تُبلَّغ بوضوح (قائمة كاملة) ولا تُمرَّر بصمت.
- لا يبدأ أي بناء داخل اللعبة دون رسالة تأكيد (لا يمكن تعطيلها من الإعدادات).
- حساب المواد دائمًا من بيانات البلوكات الفعلية، لا من نص الذكاء الاصطناعي.
- الصور (PNG/JPG) مراجع بصرية فقط — لا تُستخدم أبدًا كبيانات بناء؛ أي ملف
  بصيغة أخرى غير المدعومة يُرفض مع رسالة مفهومة.
- لا نسخ احتياطي مدمج ولا زر تراجع (حسب القرار 11 من المواصفة).

## الترخيص

MIT — انظر `LICENSE`. تبعيات/مراجع أطراف ثالثة موثقة في `NOTICE_THIRD_PARTY.md`.
