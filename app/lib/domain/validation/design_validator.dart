import 'package:flutter/foundation.dart';

import '../model/design.dart';

/// Semantic + structural validation for `schematic3d-build` documents.
/// Kept deliberately in lockstep with the Python implementation
/// (converter/src/schematic3d_converter/validate.py). The shared golden
/// fixtures under assets/examples (broken-*.json) are asserted against BOTH
/// implementations in the test suites.
@immutable
class Issue {
  const Issue(this.level, this.code, this.message, [this.path]);
  static const error = 'error';
  static const warning = 'warning';

  final String level;
  final String code;
  final String message;
  final String? path;

  bool get isError => level == error;

  Map<String, Object?> toJson() =>
      {'level': level, 'code': code, 'message': message, if (path != null) 'path': path};

  @override
  String toString() => '[$level] $code${path != null ? ' @$path' : ''}: $message';
}

class ValidationReport {
  final List<Issue> issues = [];
  bool truncated = false;

  static const maxIssues = 200;

  void error(String code, String message, [String? path]) =>
      _add(Issue.error, code, message, path);
  void warning(String code, String message, [String? path]) =>
      _add(Issue.warning, code, message, path);

  void _add(String level, String code, String message, String? path) {
    if (issues.length >= maxIssues) {
      truncated = true;
      return;
    }
    issues.add(Issue(level, code, message, path));
  }

  List<Issue> get errors => issues.where((i) => i.isError).toList(growable: false);
  List<Issue> get warnings => issues.where((i) => !i.isError).toList(growable: false);
  bool get ok => errors.isEmpty;

  Map<String, Object?> toJson() => {
        'valid': ok,
        'errorCount': errors.length,
        'warningCount': warnings.length,
        'truncated': truncated,
        'issues': issues.map((i) => i.toJson()).toList(),
      };
}

class Limits {
  static const maxDimension = 512;
  static const maxBlocks = 2000000;
  static const maxPalette = 4096;
  static const maxName = 200;
  static const maxListFields = 4096;

  static final blockIdRe = RegExp(r'^[a-z0-9_.-]+:[a-z0-9_./-]+$');
  static final stateKeyRe = RegExp(r'^[a-z][a-z0-9_]*$');
}

/// Result of validation: either a Design or the report (report always
/// returned so the UI can show warnings for accepted files).
class ValidationResult {
  ValidationResult(this.design, this.report);
  final Design? design;
  final ValidationReport report;
  bool get ok => report.ok && design != null;
}

ValidationResult validateSchematicDoc(Map<String, Object?> doc, {
  String Function(String id)? classifyId,
}) {
  final rep = ValidationReport();

  if (doc['format'] != 'schematic3d-build') {
    rep.error('format', 'format must be "schematic3d-build"', '\$.format');
  }
  if (doc['schemaVersion'] != 1) {
    rep.error('schemaVersion', 'unsupported schemaVersion ${doc['schemaVersion']}',
        '\$.schemaVersion');
  }

  final name = doc['name'];
  if (name is! String || name.isEmpty || name.length > Limits.maxName) {
    rep.error('name.type', 'name must be a string of 1..200 chars', '\$.name');
  }
  var description = doc['description'];
  if (description != null && (description is! String || description.length > 4000)) {
    rep.warning('description.type', 'description ignored (must be string ≤4000)');
    description = null;
  }

  int dx = 0, dy = 0, dz = 0;
  final dims = doc['dimensions'];
  if (dims is! Map) {
    rep.error('dimensions.type', 'dimensions must be an object', '\$.dimensions');
  } else {
    dx = _dim(dims['x'], 'x', rep);
    dy = _dim(dims['y'], 'y', rep);
    dz = _dim(dims['z'], 'z', rep);
  }

  // ---- palette (with duplicate merge like the python path) --------------
  final paletteRaw = doc['palette'];
  final mergedEntries = <PaletteEntry>[];
  final mergeMap = <int, int>{}; // original idx -> merged idx (-1 invalid)
  final seenIdx = <String, int>{};
  if (paletteRaw is! List || paletteRaw.isEmpty) {
    rep.error('palette.type', 'palette must be a non-empty array', '\$.palette');
  } else {
    if (paletteRaw.length > Limits.maxPalette) {
      rep.error('palette.size', 'palette too large (${paletteRaw.length})', '\$.palette');
    }
    for (var i = 0; i < paletteRaw.length; i++) {
      final entry = paletteRaw[i];
      final path = '\$.palette[$i]';
      if (entry is! Map) {
        rep.error('palette.entry', 'palette entry $i must be an object', path);
        mergeMap[i] = -1;
        continue;
      }
      final id = entry['id'];
      if (id is! String || !Limits.blockIdRe.hasMatch(id)) {
        rep.error('palette.id', 'invalid block id: $id', '$path.id');
        mergeMap[i] = -1;
        continue;
      }
      final states = <String, Object>{};
      final rawStates = entry['states'];
      if (rawStates is Map) {
        rawStates.forEach((k, v) {
          if (k is! String || !Limits.stateKeyRe.hasMatch(k)) {
            rep.error('palette.state', 'invalid state name $k', '$path.states');
          } else if (v is bool || v is int || (v is String && v.length <= 64)) {
            states[k] = v as Object;
          } else {
            rep.error('palette.state', 'state $k: unsupported value', '$path.states');
          }
        });
      } else if (rawStates != null && rawStates is! Map) {
        rep.error('palette.states', 'states must be an object', '$path.states');
      }
      final pe = PaletteEntry(id, states);
      final key = _permKey(id, states);
      final first = seenIdx[key];
      if (first != null) {
        rep.warning('palette.duplicate',
            'palette entry $i duplicates entry $first; will merge', path);
        mergeMap[i] = first;
      } else {
        seenIdx[key] = mergedEntries.length;
        mergedEntries.add(pe);
        mergeMap[i] = mergedEntries.length - 1;
      }
      if (classifyId != null) {
        final verdict = classifyId(id);
        if (verdict == 'unknown') {
          rep.warning('palette.id.unknown',
              'block id "$id" is not in the static Bedrock snapshot; '
              'it will be validated in-game', '$path.id');
        }
      }
    }
  }

  // ---- blocks -------------------------------------------------------------
  final blocks = <BlockEntry>[];
  final coordsSeen = <(int, int, int), int>{};
  final blocksRaw = doc['blocks'];
  if (blocksRaw is! List || blocksRaw.isEmpty) {
    rep.error('blocks.type', 'blocks must be a non-empty array', '\$.blocks');
  } else {
    if (blocksRaw.length > Limits.maxBlocks) {
      rep.error('blocks.size', 'too many blocks (${blocksRaw.length})', '\$.blocks');
    }
    for (var i = 0; i < blocksRaw.length; i++) {
      final b = blocksRaw[i];
      final path = '\$.blocks[$i]';
      if (b is! Map) {
        rep.error('blocks.entry', 'block entry $i must be an object', path);
        continue;
      }
      final x = b['x'], y = b['y'], z = b['z'], p = b['paletteIndex'];
      var ok = true;
      if (x is! int || y is! int || z is! int) {
        rep.error('blocks.coord', 'x/y/z must be integers', path);
        ok = false;
      } else {
        if (dx > 0 && (x < 0 || x >= dx)) {
          rep.error('blocks.bounds', 'x=$x outside dimensions (0..${dx - 1})', path);
          ok = false;
        }
        if (dy > 0 && (y < 0 || y >= dy)) {
          rep.error('blocks.bounds', 'y=$y outside dimensions (0..${dy - 1})', path);
          ok = false;
        }
        if (dz > 0 && (z < 0 || z >= dz)) {
          rep.error('blocks.bounds', 'z=$z outside dimensions (0..${dz - 1})', path);
          ok = false;
        }
      }
      var pi = -1;
      if (p is! int || p < 0 || p >= (paletteRaw is List ? paletteRaw.length : 0)) {
        rep.error('blocks.paletteIndex', 'paletteIndex invalid: $p', path);
        ok = false;
      } else {
        pi = mergeMap[p] ?? -1;
        if (pi < 0 || pi >= mergedEntries.length) {
          rep.error('blocks.paletteIndex', 'paletteIndex $p references invalid entry',
              path);
          ok = false;
        }
      }
      if (!ok || x is! int || y is! int || z is! int) continue;
      final key = (x, y, z);
      if (coordsSeen.containsKey(key)) {
        rep.error('blocks.duplicate',
            'coordinate ($x,$y,$z) already defined at block '
            '${coordsSeen[key]}', path);
        continue;
      }
      coordsSeen[key] = i;
      blocks.add(BlockEntry(x, y, z, pi));
    }
  }

  // ---- layers ---------------------------------------------------------------
  final layers = <Layer>[];
  final layerIds = <String>{};
  final layersRaw = doc['layers'];
  if (layersRaw != null && layersRaw is! List) {
    rep.error('layers.type', 'layers must be an array', '\$.layers');
  }
  for (final (i, l) in _indexed(layersRaw)) {
    final path = '\$.layers[$i]';
    if (l is! Map) {
      rep.error('layers.entry', 'layer must be an object', path);
      continue;
    }
    final id = l['id'];
    if (id is! String || id.isEmpty || id.length > 80) {
      rep.error('layers.id', 'layer id must be a string (1..80)', path);
      continue;
    }
    if (!layerIds.add(id)) {
      rep.error('layers.duplicate', 'duplicate layer id "$id"', path);
      continue;
    }
    final y0 = l['yMin'], y1 = l['yMax'];
    if (y0 is! int || y1 is! int || y0 < 0 || y1 < 0 || y0 > y1 ||
        (dy > 0 && y1 >= dy)) {
      rep.error('layers.range', 'layer "$id" range invalid for height $dy', path);
      continue;
    }
    final lname = l['name'];
    layers.add(Layer(id: id, yMin: y0, yMax: y1, name: lname is String ? lname : null));
  }

  // ---- rooms ---------------------------------------------------------------
  final rooms = <Room>[];
  final roomIds = <String>{};
  final roomsRaw = doc['rooms'];
  if (roomsRaw != null && roomsRaw is! List) {
    rep.error('rooms.type', 'rooms must be an array', '\$.rooms');
  }
  for (final (i, r) in _indexed(roomsRaw)) {
    final path = '\$.rooms[$i]';
    if (r is! Map) {
      rep.error('rooms.entry', 'room must be an object', path);
      continue;
    }
    final id = r['id'];
    if (id is! String || id.isEmpty || id.length > 80 || !roomIds.add(id)) {
      rep.error('rooms.id', 'room id missing/duplicate', path);
      continue;
    }
    final b = r['bounds'];
    if (b is! Map) {
      rep.error('rooms.bounds', 'bounds object required', path);
      continue;
    }
    final x0 = b['x0'], z0 = b['z0'], x1 = b['x1'], z1 = b['z1'];
    if (x0 is! int || z0 is! int || x1 is! int || z1 is! int) {
      rep.error('rooms.bounds', 'bounds need ints', path);
      continue;
    }
    if (x0 > x1 || z0 > z1) {
      rep.error('rooms.bounds', 'room "$id" bounds inverted', path);
      continue;
    }
    if (dx > 0 && (x0 < 0 || z0 < 0 || x1 >= dx || z1 >= dz)) {
      rep.error('rooms.bounds', 'room "$id" bounds outside footprint', path);
      continue;
    }
    final lid = r['layerId'];
    String? layerId;
    if (lid is String) {
      if (layerIds.contains(lid)) {
        layerId = lid;
      } else {
        rep.warning('rooms.layer', 'room "$id" references unknown layer "$lid"', path);
      }
    }
    final rname = r['name'];
    rooms.add(Room(id: id, bounds: (x0, z0, x1, z1),
        name: rname is String ? rname : null, layerId: layerId));
  }

  var metadata = doc['metadata'];
  if (metadata != null && metadata is! Map) {
    rep.warning('metadata.type', 'metadata must be an object; ignored');
    metadata = null;
  }

  final te = doc['targetEdition'];
  if (te != null && te != 'bedrock') {
    rep.warning('targetEdition',
        'targetEdition="$te"; this app targets Bedrock — conversion report '
        'will show every changed block', '\$.targetEdition');
  }

  if (dx > 0 && dy > 0 && dz > 0) {
    final vol = dx * dy * dz;
    if (vol > 16 * 1024 * 1024) {
      rep.error('volume', 'bounding volume $vol exceeds 16M cells');
    }
    if (blocks.length > vol) {
      rep.error('volume.overflow',
          '${blocks.length} blocks cannot fit in volume $vol after dedup');
    }
  }

  if (rep.ok && dx > 0 && dy > 0 && dz > 0) {
    final design = Design(
      name: name is String ? name : 'Untitled',
      description: description is String ? description : null,
      dimensions: (dx, dy, dz),
      palette: mergedEntries,
      blocks: blocks,
      layers: layers,
      rooms: rooms,
      metadata: metadata is Map
          ? Map<String, Object?>.from(metadata)
          : const {},
    );
    return ValidationResult(design, rep);
  }
  return ValidationResult(null, rep);
}

int _dim(Object? v, String axis, ValidationReport rep) {
  if (v is! int || v < 1 || v > Limits.maxDimension) {
    rep.error('dimensions.range',
        'dimensions.$axis=$v out of range 1..${Limits.maxDimension}',
        '\$.dimensions');
    return 0;
  }
  return v;
}

Iterable<(int, Object?)> _indexed(Object? list) sync* {
  if (list is List) {
    for (var i = 0; i < list.length && i < Limits.maxListFields; i++) {
      yield (i, list[i]);
    }
  }
}

String _permKey(String id, Map<String, Object> states) {
  final parts = states.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return '$id{${parts.map((e) => '${e.key}=${e.value}').join(',')}}';
}
