#!/usr/bin/env python3
"""Generate app/lib/l10n/app_{en,ar,fr}.arb from one table (key parity
guaranteed). Run after editing the table; CI re-checks parity."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "lib" / "l10n"

# key -> (en, ar, fr, optional placeholder dict for @@)
T: dict[str, tuple[str, str, str]] = {
    "appTitle": ("Schematic 3D", "مخطط ثلاثي الأبعاد", "Schematic 3D"),
    "navLibrary": ("Library", "المكتبة", "Bibliothèque"),
    "navImport": ("Import", "استيراد", "Importer"),
    "navGuide": ("Guide", "الدليل", "Guide"),
    "navLog": ("Log", "السجل", "Journal"),
    "navSettings": ("Settings", "الإعدادات", "Réglages"),

    "searchHint": ("Search designs…", "ابحث في التصاميم…", "Rechercher…"),
    "categoryAll": ("All", "الكل", "Tout"),
    "sortLabel": ("Sort", "ترتيب", "Ordre"),
    "sortByName": ("Name", "الاسم", "Nom"),
    "sortBySize": ("Size", "الحجم", "Taille"),
    "sortByBlocks": ("Blocks", "عدد البلوكات", "Blocs"),
    "sortByDate": ("Date", "التاريخ", "Date"),
    "sortDescending": ("Descending order", "ترتيب تنازلي", "Ordre décroissant"),

    "emptyLibrary": ("No designs yet", "لا توجد تصاميم بعد", "Aucun dessin"),
    "emptyLibraryHint": ("Use the Import tab to load .json / .mcstructure / .schem files",
                          "استخدم تبويب استيراد لتحميل ملفات json./mcstructure/.schem",
                          "Ouvrez l'onglet Importer pour charger .json / .mcstructure / .schem"),
    "libraryCount": ("{n} design(s)", "{n} تصميم", "{n} dessin(s)"),

    "categoryPalaces": ("Palaces", "قصور", "Palais"),
    "categoryHouses": ("Houses", "منازل", "Maisons"),
    "categoryTowers": ("Towers", "أبراج", "Tours"),
    "categoryBridges": ("Bridges", "جسور", "Ponts"),
    "categoryFarms": ("Farms", "مزارع", "Fermes"),
    "categoryDecor": ("Decor", "ديكورات", "Décorations"),
    "categoryIndustrial": ("Industrial", "صناعي", "Industriel"),
    "categoryOther": ("Other", "أخرى", "Autre"),

    "detailTab3d": ("3D", "ثلاثي الأبعاد", "3D"),
    "detailTabPlan": ("Floor plan", "مخطط طوابق", "Plan d'étage"),
    "detailTabMaterials": ("Materials", "المواد", "Matériaux"),
    "detailTabInfo": ("Info", "معلومات", "Infos"),
    "layersTitle": ("Layers", "الطبقات", "Couches"),
    "roomsTitle": ("Rooms", "الغرف", "Pièces"),
    "showAllLayers": ("All layers", "كل الطبقات", "Toutes les couches"),
    "resetView": ("Reset view", "إعادة ضبط العرض", "Réinitialiser la vue"),
    "dragRotateHint": ("Drag to rotate · pinch to zoom · double-tap resets",
                       "اسحب للتدوير · قرّص للتكبير · نقرة مزدوجة لإعادة الضبط",
                       "Glisser pour pivoter · pincer pour zoomer · double-tap = reset"),
    "sliceRange": ("Slice Y {lo}–{hi}", "شريحة Y {lo}–{hi}", "Coupe Y {lo}–{hi}"),
    "moveSliceUp": ("Next level", "المستوى التالي", "Niveau suivant"),
    "moveSliceDown": ("Previous level", "المستوى السابق", "Niveau précédent"),

    "totalBlocks": ("Total blocks", "إجمالي البلوكات", "Blocs au total"),
    "distinctMaterials": ("Distinct materials", "عدد المواد", "Matériaux distincts"),
    "blockCount": ("blocks", "بلوك", "blocs"),
    "stacks": ("stacks", "مكدّس", "piles"),
    "infoName": ("Name", "الاسم", "Nom"),
    "infoDescription": ("Description", "الوصف", "Description"),
    "infoSource": ("Imported from", "مستورد من", "Importé de"),
    "infoDims": ("Dimensions", "الأبعاد", "Dimensions"),
    "infoPalette": ("Palette", "لوحة البلوكات", "Palette"),
    "infoDropped": ("Dropped blocks", "بلوكات محذوفة", "Blocs supprimés"),
    "infoNotes": ("Conversion notes", "ملاحظات التحويل", "Notes de conversion"),
    "renameAction": ("Rename", "إعادة تسمية", "Renommer"),
    "moveCategory": ("Move to folder", "نقل إلى مجلد", "Déplacer vers dossier"),
    "deleteAction": ("Delete", "حذف", "Supprimer"),
    "confirmDelete": ("Delete design?", "حذف التصميم؟", "Supprimer le dessin ?"),
    "confirmDeleteMsg": ("This removes the design and its files from the app only.",
                          "سيُحذف التصميم وملفاته من التطبيق فقط.",
                          "Cela supprime le dessin et ses fichiers de l'application uniquement."),
    "deleted": ("Deleted", "تم الحذف", "Supprimé"),

    "importPick": ("Pick a file", "اختر ملفًا", "Choisir un fichier"),
    "importPickHint": ("Supported: schematic3d JSON, .mcstructure (Bedrock), .schem (Sponge v2 / Litematica), .schematic",
                        "المدعوم: JSON الخاص بالتطبيق، ‎.mcstructure (Bedrock)، ‎.schem (Sponge v2 / Litematica)، ‎.schematic",
                        "Pris en charge : JSON schematic3d, .mcstructure (Bedrock), .schem (Sponge v2 / Litematica), .schematic"),
    "importWorking": ("Converting…", "جارٍ التحويل…", "Conversion…"),
    "importResultOk": ("Import completed", "تم الاستيراد بنجاح", "Import réussi"),
    "importResultPartial": ("Imported with warnings", "تم الاستيراد مع تحذيرات", "Importé avec avertissements"),
    "importResultFailed": ("Conversion failed", "فشل التحويل", "Échec de la conversion"),
    "importFailKept": ("The original file was kept in the app storage and recorded in the log.",
                        "تم الاحتفاظ بالملف الأصلي في تخزين التطبيق وتسجيله في السجل.",
                        "Le fichier original a été conservé dans le stockage de l'app et consigné dans le journal."),
    "errorsTitle": ("Errors", "أخطاء", "Erreurs"),
    "warningsTitle": ("Warnings", "تحذيرات", "Avertissements"),
    "unsupportedTitle": ("Unsupported blocks (dropped)", "بلوكات غير مدعومة (حُذفت)", "Blocs non pris en charge (retirés)"),
    "unsupportedHint": ("These blocks have no Bedrock equivalent in this version. The design remains valid without them.",
                         "لا يوجد مقابل Bedrock لهذه البلوكات في هذا الإصدار، والتصميم صالح بدونها.",
                         "Ces blocs n'ont pas d'équivalent Bedrock dans cette version ; le dessin reste valide sans eux."),
    "noIssues": ("No issues", "لا توجد مشاكل", "Aucun problème"),
    "saveToLibrary": ("Save to library", "حفظ في المكتبة", "Enregistrer"),
    "copy": ("Copy", "نسخ", "Copier"),
    "copied": ("Copied to clipboard", "تم النسخ إلى الحافظة", "Copié dans le presse-papiers"),
    "ok": ("OK", "حسنًا", "OK"),
    "cancel": ("Cancel", "إلغاء", "Annuler"),
    "close": ("Close", "إغلاق", "Fermer"),

    "exportJson": ("Export JSON", "تصدير JSON", "Exporter JSON"),
    "exportMcstructure": ("Export .mcstructure", "تصدير ‎.mcstructure", "Exporter .mcstructure"),
    "exportAddon": ("Export as MCAddon pack", "تصدير كحزمة MCAddon", "Exporter en MCAddon"),
    "exportAddonBuilding": ("Building .mcaddon…", "جارٍ بناء الحزمة…", "Construction du .mcaddon…"),
    "exportAddonShareHint": ("Open the shared file with Minecraft (or copy it to your device), then activate both packs in your world.",
                               "افتح الملف المشارك بميانكرفت (أو انسخه لجهازك) ثم فعّل الحزمتين في عالمك.",
                               "Ouvrez le fichier partagé avec Minecraft (ou copiez-le sur l'appareil), puis activez les deux packs dans votre monde."),

    "promptFab": ("Copy AI prompt", "نسخ برومبت الذكاء الاصطناعي", "Copier le prompt IA"),
    "promptSheetTitle": ("Prompt for external AI", "برومبت للذكاء الاصطناعي الخارجي", "Prompt pour IA externe"),
    "promptIncludeCurrent": ("Include current design JSON", "تضمين JSON التصميم الحالي", "Inclure le JSON du dessin actuel"),
    "promptExtraNotesHint": ("Extra notes (optional)", "ملاحظات إضافية (اختياري)", "Notes supplémentaires (facultatif)"),
    "promptCopied": ("Prompt copied — paste it into ChatGPT / Claude / Gemini", "تم نسخ البرومبت — الصقه في ChatGPT / Claude / Gemini", "Prompt copié — collez-le dans ChatGPT / Claude / Gemini"),
    "promptOfflineNote": ("This app has no built-in AI and no network calls; it only copies the text.",
                            "لا يحتوي التطبيق على ذكاء اصطناعي مدمج ولا اتصالات شبكة؛ ينسخ النص فقط.",
                            "L'application n'a aucune IA intégrée ni appel réseau ; elle copie uniquement le texte."),

    "logStatusSuccess": ("Success", "نجاح", "Succès"),
    "logStatusPartial": ("With warnings", "مع تحذيرات", "Avec avertissements"),
    "logStatusFailed": ("Failed", "فشل", "Échec"),
    "logColFile": ("File", "الملف", "Fichier"),
    "logColStatus": ("Status", "الحالة", "Statut"),
    "logOpenDesign": ("Open design", "فتح التصميم", "Ouvrir le dessin"),
    "logClear": ("Clear log", "تفريغ السجل", "Vider le journal"),
    "logCleared": ("Log cleared", "تم تفريغ السجل", "Journal vidé"),
    "logUnsupportedN": ("{n} unsupported block type(s)", "{n} نوع بلوك غير مدعوم", "{n} type(s) de bloc non pris en charge"),

    "settingsLanguage": ("Language", "اللغة", "Langue"),
    "languageSystem": ("System", "لغة النظام", "Système"),
    "settingsDefaultView": ("Default viewer", "العارض الافتراضي", "Visionneuse par défaut"),
    "settingsBatchSpeed": ("Default batch speed", "سرعة البناء الجماعي الافتراضية", "Vitesse par défaut de la construction par lots"),
    "settingsBatchSpeedHint": ("Blocks per tick — the in-game slider overrides this per session.",
                                 "بلوك لكل tick — يُلغِي المؤثر داخل اللعبة هذا القيمة لكل جلسة.",
                                 "Blocs par tick — le curseur en jeu prime par session."),
    "settingsAbout": ("About", "حول", "À propos"),
    "settingsAboutText": ("Schematic 3D v1.0.0 — fully offline. Target: Minecraft Bedrock 26.40.5 with the bundled Schematic 3D Builder add-on.",
                            "مخطط ثلاثي الأبعاد v1.0.0 — يعمل دون اتصال بالكامل. الهدف: Minecraft Bedrock 26.40.5 مع إضافة Schematic 3D Builder المرفقة.",
                            "Schematic 3D v1.0.0 — 100% hors ligne. Cible : Minecraft Bedrock 26.40.5 avec l'add-on Schematic 3D Builder fourni."),
    "settingsConfirmTitle": ("Confirmation before building", "تأكيد قبل البناء", "Confirmation avant construction"),
    "settingsConfirmAlways": ("Always required (safety)", "مطلوب دائمًا ( للسلامة)", "Toujours requise (sécurité)"),

    "guideAddonTitle": ("Installing the add-on", "تركيب الإضافة", "Installer l'add-on"),
    "guideBuildFlow": ("Build flow", "مسار البناء", "Flux de construction"),

    "failureFileUnreadable": ("Cannot read the file", "تعذّرت قراءة الملف", "Lecture du fichier impossible"),
    "failureUnsupportedFormat": ("Unsupported file format", "صيغة ملف غير مدعومة", "Format non pris en charge"),
    "failureInvalidDesign": ("Invalid design document", "مستند تصميم غير صالح", "Document de dessin invalide"),
    "failureDatabase": ("Local database error", "خطأ في قاعدة البيانات المحلية", "Erreur de base de données locale"),
    "failureExport": ("Export failed", "فشل التصدير", "Échec de l'export"),
    "failurePermissionDenied": ("Permission denied", "الإذن مرفوض", "Permission refusée"),
    "failureCancelled": ("Cancelled", "تم الإلغاء", "Annulé"),
}

MULTI: dict[str, tuple[str, str, str]] = {
    "guideSteps": (
        "1. Import a design (JSON / .mcstructure / .schem) — unsupported blocks are listed, the original file is never lost.\n"
        "2. Check the 3D preview, layers and floor plans; open Materials to see exact quantities.\n"
        "3. Export the design as MCAddon pack (or keep it in the library).\n"
        "4. On the phone: open the .mcaddon with Minecraft, activate both packs in the world settings (Beta APIs on).\n"
        "5. In game: use the S3D Menu item or chat commands starting with !s3d — preview the hologram, move/rotate/set height, toggle layers & rooms, then build manually or in batches after the confirmation prompt.",
        "1. استورد تصميمًا (JSON / ‎.mcstructure‎ / ‎.schem‎) — تُعرض البلوكات غير المدعومة ولا يضيع الملف الأصلي أبدًا.\n"
        "2. راجع المعاينة ثلاثية الأبعاد والطبقات والمخططات، وافتح المواد لمعرفة الكميات الدقيقة.\n"
        "3. صدّر التصميم كحزمة MCAddon (أو احتفظ به في المكتبة).\n"
        "4. على الهاتف: افتح ملف ‎.mcaddon‎ مع ماينكرافت وفعّل الحزمتين في إعدادات العالم (Beta APIs مفعّلة).\n"
        "5. داخل اللعبة: استخدم عنصر قائمة S3D أو أوامر الدردشة التي تبدأ بـ !s3d — عاين الهولوجرام، حرّك/أدِر/ارفع، بدّل الطبقات والغرف، ثم ابنِ يدويًا أو جماعيًا بعد رسالة التأكيد.",
        "1. Importez un dessin (JSON / .mcstructure / .schem) — les blocs non pris en charge sont listés, le fichier original n'est jamais perdu.\n"
        "2. Vérifiez l'aperçu 3D, les couches et les plans ; ouvrez Matériaux pour les quantités exactes.\n"
        "3. Exportez le dessin en pack MCAddon (ou gardez-le dans la bibliothèque).\n"
        "4. Sur le téléphone : ouvrez le .mcaddon avec Minecraft, activez les deux packs (Beta APIs activées).\n"
        "5. En jeu : item S3D Menu ou commandes !s3d — hologramme, déplacer/tourner/hauteur, couches & pièces, puis construction manuelle ou par lots après confirmation.",
    ),
    "guideLimitations": (
        "• Android scoped storage prevents writing into Minecraft game folders — the app exports files you open/import manually.\n"
        "• Co-located (waterlogged) blocks in .mcstructure files are reported and skipped — v1 formats are single-block-per-cell.\n"
        "• Inventory checking in the add-on is only enforced where the Script API can read it; otherwise build proceeds and failures are reported per block.",
        "• تخزين Android المقيّد يمنع الكتابة في مجلدات لعبة ماينكرافت — يصدّر التطبيق ملفات تفتحها/تستوردها يدويًا.\n"
        "• البلوكات المتداخلة (waterlogged) في ملفات ‎.mcstructure‎ تُبلَّغ ويُتجاهلها — صيغة v1 كتلة واحدة لكل خلية.\n"
        "• فحص الحقائب داخل الإضافة يُطبَّق فقط حيث تتيح واجهة السكربت قراءتها؛ وإلا تستمر العملية وتُسجَّل الإخفاقات لكل بلوك.",
        "• Le stockage cloisonné d'Android empêche d'écrire dans les dossiers du jeu — l'app exporte des fichiers à importer manuellement.\n"
        "• Les blocs superposés (waterlogged) des .mcstructure sont signalés puis ignorés — le format v1 est mono-bloc par cellule.\n"
        "• Le contrôle d'inventaire en jeu n'est appliqué que là où l'API Script permet de lire ; sinon la construction continue et les échecs sont consignés bloc par bloc.",
    ),
    "guideAddonCommands": (
        "!s3d — open the add-on menu in chat\n"
        "!s3d build — start the batch build (asks confirmation first)\n"
        "!s3d pause / !s3d resume — pause or resume a running batch\n"
        "!s3d speed 32 — set blocks placed per tick (1–256)\n"
        "!s3d up / !s3d down — raise/lower the hologram",
        "!s3d — فتح قائمة الإضافة في الدردشة\n"
        "!s3d build — بدء البناء الجماعي (يطلب تأكيدًا أولًا)\n"
        "!s3d pause / !s3d resume — إيقاف مؤقت أو استئناف الدفعة\n"
        "!s3d speed 32 — عدد البلوكات لكل tick (1–256)\n"
        "!s3d up / !s3d down — رفع/خفض الهولوجرام",
        "!s3d — ouvre le menu de l'add-on en chat\n"
        "!s3d build — lance la construction par lots (confirmation d'abord)\n"
        "!s3d pause / !s3d resume — pause / reprise du lot\n"
        "!s3d speed 32 — blocs posés par tick (1–256)\n"
        "!s3d up / !s3d down — monter/descendre l'hologramme",
    ),
}


def main(check: bool = False) -> int:
    import difflib
    failed = 0
    for i, loc in enumerate(("en", "ar", "fr")):
        data: dict = {"@@locale": loc}
        for key, vals in T.items():
            data[key] = vals[i]
            meta: dict = {"description": key}
            ph = placeholders_for(key)
            if ph:
                meta["placeholders"] = ph
            data[f"@{key}"] = meta
        for key, vals in MULTI.items():
            data[key] = vals[i]
            data[f"@{key}"] = {"description": key}
        out = OUT / f"app_{loc}.arb"
        payload = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if check:
            current = out.read_text(encoding="utf-8") if out.exists() else ""
            if current != payload:
                print(f"[check] {out.name} is stale — run tool/gen_arb.py")
                diff = difflib.unified_diff(
                    current.splitlines(), payload.splitlines(), lineterm="", n=1)
                print("\n".join(list(diff)[:20]))
                failed += 1
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(payload, encoding="utf-8")
        print("wrote", out)
    return 1 if failed else 0


def placeholders_for(key: str) -> dict | None:
    import re
    vals = T[key]
    names: set[str] = set()
    for v in vals:
        names |= set(re.findall(r"\{(\w+)\}", v))
    if not names:
        return None
    return {n: {"type": "int" if n == "n" else "Object"} for n in sorted(names)}


if __name__ == "__main__":
    import sys
    raise SystemExit(main(check="--check" in sys.argv))
