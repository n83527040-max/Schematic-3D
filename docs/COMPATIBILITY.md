# تحقق التوافق — Minecraft Bedrock 26.40.5 Android

## لماذا 26.40.5 تحديدًا

- صفحة الإصدارات الرسمية (minecraft.wiki/w/Bedrock_Edition_26.40، جُلبت
  2026-10-29): تحديث 26.40 = داخليًا **1.26.40**، وإصدار الأندرويد
  **1.26.40.5** بتاريخ 2026-08-04 — أي أن الهدف حقيقي ومطابق لما طلبته
  المواصفة.
- حزم الإضافة تحمل `min_engine_version: [1, 26, 40]` في الـmanifests.

## منهجية التحقق (بلا جهاز — موصوفة بصدق)

1. **typings رسمية**: حُزم `@minecraft/server` و `@minecraft/server-ui`
   لاصدار اللعبة (نُسخة في `_refs/mcapi/node_modules`) — **كل** نداء API في
   سكربتات الإضافة طوبق مع توقيعه في هذه الملفات؛ النداءات غير الموجودة
   استُبعدت:
   - لا `Dimension.runCommandAsync` → `runCommand` (متزامن) + `system.runJob`
     للتقسيم على الإطارات.
   - لا `Dimension.setBlock(String)` → `setBlockType` / `setBlockPermutation`.
   - لا `Player.isCreativeMode` → `getGameMode()`.
   - لا `Player.localeId` → اللغة تُخزَّن في config الإضافة.
   - `ModalFormData.slider(label, min, max, {valueStep, defaultValue})`
     (بالتموضع) و`MessageFormResponse.selection` — كما في d.ts لا كما في
     المراجع القديمة.
2. **Construct v1.2.0** (نفس حقبة 26.40؛ HEAD الخاص به استُخدم كمرجع، وليس
   إصدارات 26.50 الأحدث): أكّدت نمط manifest+events+events-per-block
   (`beforeEvents.chatSend` قابل للإلغاء، `afterEvents.playerPlaceBlock/
   playerBreakBlock`، `itemUse.source: Player`) وأن `world.getDimension` +
   `getAllPlayers` + `getTopmostBlock` (محمي بـtry) متاحة.
3. **Bedrockmatika** (مرجع إضافات عمل فعلية) أكّدت أن الهولوغرامات عبر بلوكات
   وهمية/شفافة لا تحتاج Beta APIs خارج المجموعة المعتادة، وتعمل على خادم
   مستقر 2.0.0 — لذلك صُمم s3d_holo_*/ghost بلوكات بدل entity-bound displays.
4. اختبارات node (29/29) للمحرك: الطابور، الدوران، bitmap التعارض،
   pause/resume، جولة البناء، tint vectors مشتركة مع Dart.

## خيارات متوافق-مُعلنة

| القرار | البديل المرفوض | السبب |
|---|---|---|
| أوامر دردشة `!s3d ...` | CustomCommandRegistry | تجريبية متقلبة عبر الإصدارات؛Construct v1.2.0 نفسه لم يعتمد عليها |
| ModalForms | ScreenUI panels | غير مكتملة الاستقرار على 26.40؛Forms تغطي كل المسارات |
| بلوكات ghost شفافة (13) + outline | holographic entities | لا حاجة لإضافات entity موثقة؛أرخص وأبسط للفحص |
| `runCommand` متزامن خلف runJob | `runCommandAsync` | غير موجود في 1.26.40 typings |
| قراءة الجرد اختيارية (gate) | رفض البناء إذا تعذر | `container.getItem/find` مثبتة typingًا لا جهازًا؛ الفشل الجزئي يُبلَّك لكل بلوك بدل منع المستخدم |

## خطة الاختبار اليدوي على جهاز (عند توفر هاتف + Bedrock 26.40.5)

1. ثبّت `dist/Schematic3DBuilder.mcaddon` وفعّل الحزمتين + Beta APIs في عالم
   إبداعي.
2. `!s3d` → القائمة: اختر cottage12x8x12 → تحقق من الهولوغرام والعدّاد
   (1032≠؛ 848 بلوكًا متوقع للتصميم).
3. حرّك ±1، دوّر 90°، ارفع/اخفض — يجب أن يعيد progress bitmap الضبط عند
   النقل/التدوير (سلوك موثق في state.js).
4. طبّق فحص التعارض: ابنِ فوق صخور — يجب أن تظهر رسالة تأكيد قبل البناء مع
   تعداد التعارضات، ثم لا يوضع أي بلوك تحت الأرضيات القديمة.
5. batch build بسرعة 32: راقب pause/resume واستئناف التقدّم من نفس الخطوة؛
   أوقف mid-batch وتحقق من سجل `config.batchLog`.
6. تحقق المخزون: خذ وضع Adventure بدون مواد → البناء اليدوي يجب أن يرفض
   التوزيع ويسجل insufficientInventory (إن لم يُفعَّل gate فليتقدم ويوثق
   الفشل لكل بلوك — السلوك الموثق أعلاه).
7. صدّر من التطبيق تصميمًا كـ mcaddon مخصص وثبّته فوق النسخة الأصلية —
   يجب أن يظهر التصميم الجديد في القائمة بنفس الأبعاد والمواد.
