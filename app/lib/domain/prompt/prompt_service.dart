import 'dart:convert';

import '../formats/export_json.dart';
import '../model/design.dart';

/// External-AI prompt template (spec §10): the app NEVER calls any AI.
/// This composes the official template + (optionally) the design JSON of the
/// open design; the result is copied to the clipboard for use in ChatGPT /
/// Claude / Gemini etc.
class PromptService {
  PromptService({required this.loadTemplate});

  /// asset loader injected so tests don't need rootBundle
  final Future<String> Function(String lang) loadTemplate;

  static const templateAsset = 'assets/prompts/design_prompt';

  Future<String> build({
    required String lang,
    Design? currentDesign,
    String? extraNotes,
  }) async {
    final sb = StringBuffer(await loadTemplate(lang));
    sb.write('\n\n');
    if (currentDesign != null) {
      sb.writeln('=== التصميم الحالي (JSON بصيغة schematic3d-build v1) / '
          'current design JSON ===');
      sb.writeln(const JsonEncoder.withIndent('  ')
          .convert(exportDesignJson(currentDesign)));
    }
    if (extraNotes != null && extraNotes.trim().isNotEmpty) {
      sb.writeln();
      sb.writeln('=== ملاحظات إضافية / extra notes ===');
      sb.writeln(extraNotes.trim());
    }
    return sb.toString();
  }
}
