import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';

/// Thin wrappers over platform file surfaces. All paths are app-scoped
/// (SAF via file_picker / share sheet) — the app never writes to Minecraft
/// game folders; the user imports the .mcaddon via the system (documented
/// limitation, Android scoped storage).
class FileIoService {
  const FileIoService();

  Future<({String name, Uint8List bytes})?> pickDesignFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kImportExtensions,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      // some Android SAF providers skip withData; fall back to path read
      if (f.path != null) {
        return (name: f.name, bytes: await File(f.path!).readAsBytes());
      }
      return null;
    }
    return (name: f.name, bytes: bytes);
  }

  /// Share any produced artifact (mcaddon / json / mcstructure) — user picks
  /// "Open with Minecraft" or a file manager from the sheet.
  Future<void> shareFile(String path, {String? subject}) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw const FileSystemException('file vanished before share', '');
    }
    await Share.shareXFiles(
      [XFile(path)],
      subject: subject ?? p.basename(path),
      text: 'Schematic 3D export',
    );
  }

  Future<String> saveTextFile(String fileName, String contents) async {
    final dir = await _exportDir();
    final out = File(p.join(dir.path, _safeName(fileName)));
    await out.writeAsString(contents);
    return out.path;
  }

  Future<String> saveBytes(String fileName, List<int> bytes) async {
    final dir = await _exportDir();
    final out = File(p.join(dir.path, _safeName(fileName)));
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  static Future<Directory> _exportDir() async {
    // App-scoped, survives OS temp cleanup; user-visible via share sheet only.
    Directory base;
    try {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory(p.join(base.path, 'exports'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _safeName(String n) =>
      n.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
}
