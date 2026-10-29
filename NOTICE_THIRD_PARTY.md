# إشعارات الأطراف الثالثة — THIRD-PARTY NOTICES

## اختبارات ومراجع مستخدمة في هذا المستودع
1. **Construct** (ForestOfLight) — رُاجع كمرجع وظيفي على إصدار MIT.
   - لم يُنسخ أي كود منه؛ استُخدمت البنية العامة فقط كمرجع تصميم.
   - المصدر: https://github.com/ForestOfLight/Construct (MIT, Copyright (c) 2025 ForestOfLight)
2. **Bedrockmatika web workshop site** — استُخدمت ملفات fixtures حقيقية لاختبار المحول:
   - `converter/tests/fixtures/forest-tower.mcstructure`
   - `converter/tests/fixtures/block-library-bridge.schem`
   - `converter/tests/fixtures/block-library-cabin.schem`
   - المصدر: https://github.com/freezecatcrazygg-ux/bedrockmatika-site (MIT). الملفات الأصلية تحمل
     MICROSOFT-SAMPLE-LICENSE داخلياً حيث ينطبق؛ حُفظت كما هي للاختبار فقط ولا تُوزَّن داخل APK/MCAddon.
3. **وثائق Minecraft Bedrock Script API** — npm `@minecraft/server@2.10.0-beta.1.26.40-stable`
   و `@minecraft/server-ui@2.2.0-beta.1.26.40-stable` استُخدما لتدقيق واجهات API فقط (Ms-PL / MIT حسب الحزمة)، ولم يُحزَّما في أي ناتج.

## تراخيص ملفات المشروع
كود Schematic 3D (تطبيق، إضافات، محوّل) مرخّص تحت MIT ما لم يُحدد خلاف ذلك في ملف فرعي.
