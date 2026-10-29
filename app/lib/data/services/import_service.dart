import 'dart:io';
import 'dart:typed_data';

import '../../domain/formats/design_importer.dart';
import '../../domain/formats/mcstructure_codec.dart';
import '../../domain/model/design.dart';
import '../repos/design_repository.dart';
import '../repos/import_log_repository.dart';

/// Orchestrates one import: parse → validate → (keep original always) →
/// store design + files → log. Errors NEVER destroy the original bytes:
/// they are persisted first (spec §5 acceptance criterion).
class ImportService {
  ImportService({
    required this.importer,
    required this.designs,
    required this.log,
    required this.storageRoot,
  });

  final DesignImporter importer;
  final DesignRepository designs;
  final ImportLogRepository log;
  final Directory storageRoot;

  Future<ImportOutcome> importFromBytes(
      Uint8List bytes, String fileName) async {
    final outcome = importer.importBytes(bytes, fileName: fileName);
    await persistOutcome(bytes, fileName, outcome);
    return outcome;
  }

  Future<ImportOutcome> persistOutcome(
      List<int> bytes, String fileName, ImportOutcome outcome) async {
    final name = fileName.split('/').last;
    if (outcome.ok) {
      final design = outcome.design!;
      final dropped = outcome.conversion?.droppedBlocks ?? 0;
      final struct = McstructureCodec.encode(design);
      final id = await designs.create(
        design: design,
        sourceFormat: outcome.format.name,
        originalBytes: bytes,
        mcstructureBytes: struct,
        originalFileName: name,
        droppedBlocks: dropped,
        notes: _notesFor(outcome),
        categoryKey: guessCategory(design.name),
      );
      await log.log(
        fileName: name,
        status: outcome.report.warnings.isEmpty
            ? ImportStatus.success
            : ImportStatus.partial,
        designId: id,
        sourceFormat: outcome.format.name,
        errorCount: 0,
        warningCount: outcome.report.warnings.length,
        droppedBlocks: dropped,
        unsupportedBlocks: outcome.conversion?.unsupportedBlocks ?? const [],
      );
    } else {
      // failed conversion: keep the original file anyway + full error log
      final id = await designs.recordFailedImport(
        fileName: name,
        originalBytes: bytes,
        format: outcome.format.name,
        errors: outcome.report.errors.map((e) => e.toString()).toList(),
      );
      await log.log(
        fileName: name,
        status: ImportStatus.failed,
        designId: id,
        sourceFormat: outcome.format.name,
        errorCount: outcome.report.errors.length,
        warningCount: outcome.report.warnings.length,
        droppedBlocks: outcome.conversion?.droppedBlocks ?? 0,
        unsupportedBlocks: outcome.conversion?.unsupportedBlocks ?? const [],
        message: outcome.report.errors.isEmpty
            ? null
            : outcome.report.errors.first.message,
      );
    }
    return outcome;
  }

  static String? _notesFor(ImportOutcome o) {
    final msgs = <String>[
      for (final w in o.report.warnings.take(6)) '${w.code}: ${w.message}',
    ];
    return msgs.isEmpty ? null : msgs.join('\n');
  }

  /// Lightweight keyword guessing for initial categorization; users can move
  /// designs later. Arabic + French + English keywords (spec categories).
  static String? guessCategory(String name) {
    final n = name.toLowerCase();
    bool has(List<String> k) => k.any(n.contains);
    if (has(['قصر', 'palais', 'palace', 'chateau'])) return 'palaces';
    if (has(['برج', 'تower', 'tower', 'tour'])) return 'towers';
    if (has(['جسر', 'pont', 'bridge'])) return 'bridges';
    if (has(['مزرعة', 'ferme', 'farm'])) return 'farms';
    if (has(['منزل', 'بيت', 'maison', 'house', 'cottage', 'villa'])) {
      return 'houses';
    }
    if (has(['مصنع', 'usine', 'factory', 'industrial', 'farm_'])) {
      return 'industrial';
    }
    if (has(['ديكور', 'deco', 'decor', 'statue'])) return 'decor';
    return null; // → uncategorized (folder "other" on request)
  }
}
