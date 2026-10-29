import 'package:flutter/foundation.dart';

/// A block palette permutation: id + canonicalized state map.
@immutable
class PaletteEntry {
  const PaletteEntry(this.id, [this.states = const {}]);

  final String id;
  final Map<String, Object> states;

  Map<String, Object?> toJson() => {
        'id': id,
        if (states.isNotEmpty) 'states': states,
      };

  static PaletteEntry fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('palette entry missing string id');
    }
    final rawStates = json['states'];
    final states = <String, Object>{};
    if (rawStates is Map) {
      rawStates.forEach((k, v) {
        if (k is! String) return;
        if (v is bool) {
          states[k] = v;
        } else if (v is int) {
          states[k] = v;
        } else if (v is String) {
          states[k] = v;
        }
      });
    }
    return PaletteEntry(id, states);
  }

  /// Bedrock `/setblock` style token incl. states.
  String get commandToken {
    if (states.isEmpty) return id;
    final parts = states.entries
        .map((e) =>
            '${e.key}=${e.value is bool ? ((e.value as bool) ? 'true' : 'false') : e.value}')
        .join(',');
    return '$id[$parts]';
  }

  @override
  bool operator ==(Object other) =>
      other is PaletteEntry &&
      other.id == id &&
      mapEquals(other.states, states);

  @override
  int get hashCode => Object.hash(id, states.length);

  static bool mapEquals(Map<String, Object> a, Map<String, Object> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || b[k].toString() != a[k].toString()) return false;
    }
    return true;
  }
}

@immutable
class BlockEntry {
  const BlockEntry(this.x, this.y, this.z, this.paletteIndex);

  final int x;
  final int y;
  final int z;
  final int paletteIndex;

  Map<String, Object?> toJson() =>
      {'x': x, 'y': y, 'z': z, 'paletteIndex': paletteIndex};

  static BlockEntry fromJson(Map<String, Object?> json) {
    final x = json['x'], y = json['y'], z = json['z'], p = json['paletteIndex'];
    if (x is! int || y is! int || z is! int || p is! int) {
      throw const FormatException('block entry needs int x/y/z/paletteIndex');
    }
    return BlockEntry(x, y, z, p);
  }

  (int, int, int) get key => (x, y, z);
}

@immutable
class Layer {
  const Layer({
    required this.id,
    required this.yMin,
    required this.yMax,
    this.name,
  });

  final String id;
  final int yMin;
  final int yMax;
  final String? name;

  String get displayName => name ?? id;
  bool covers(int y) => y >= yMin && y <= yMax;
  int get height => yMax - yMin + 1;

  Map<String, Object?> toJson() => {
        'id': id,
        'yMin': yMin,
        'yMax': yMax,
        if (name != null) 'name': name,
      };

  static Layer fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final y0 = json['yMin'];
    final y1 = json['yMax'];
    if (id is! String || y0 is! int || y1 is! int) {
      throw const FormatException('layer needs id/yMin/yMax');
    }
    final name = json['name'];
    return Layer(id: id, yMin: y0, yMax: y1, name: name is String ? name : null);
  }
}

@immutable
class Room {
  const Room({
    required this.id,
    required this.bounds,
    this.name,
    this.layerId,
  });

  final String id;
  final String? name;
  final String? layerId;

  /// x0, z0, x1, z1 (inclusive, design coordinates).
  final (int x0, int z0, int x1, int z1) bounds;

  int get xMin => bounds.$1;
  int get zMin => bounds.$2;
  int get xMax => bounds.$3;
  int get zMax => bounds.$4;

  bool contains(int x, int z) =>
      x >= xMin && x <= xMax && z >= zMin && z <= zMax;

  /// True when this room's band overlaps a Y slice. Rooms are plan areas;
  /// when layerId is null they span all heights.
  bool containsY(int y, {Layer? layer}) =>
      layer == null || layer.covers(y);

  String get displayName => name ?? id;

  Map<String, Object?> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (layerId != null) 'layerId': layerId,
        'bounds': {'x0': bounds.$1, 'z0': bounds.$2, 'x1': bounds.$3, 'z1': bounds.$4},
      };

  static Room fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final b = json['bounds'];
    if (id is! String || b is! Map) {
      throw const FormatException('room needs id + bounds');
    }
    final x0 = b['x0'], z0 = b['z0'], x1 = b['x1'], z1 = b['z1'];
    if (x0 is! int || z0 is! int || x1 is! int || z1 is! int) {
      throw const FormatException('room bounds need int x0/z0/x1/z1');
    }
    final name = json['name'];
    final layerId = json['layerId'];
    return Room(
      id: id,
      bounds: (x0, z0, x1, z1),
      name: name is String ? name : null,
      layerId: layerId is String ? layerId : null,
    );
  }
}

/// Complete in-memory design (schematic3d-build v1, post-validation).
class Design {
  Design({
    required this.name,
    this.description,
    required this.dimensions,
    required this.palette,
    required this.blocks,
    this.layers = const [],
    this.rooms = const [],
    this.metadata = const {},
  });

  final String name;
  final String? description;
  final (int x, int y, int z) dimensions;
  final List<PaletteEntry> palette;
  final List<BlockEntry> blocks;
  final List<Layer> layers;
  final List<Room> rooms;
  final Map<String, Object?> metadata;

  int get blockCount => blocks.length;
  int get volume => dimensions.$1 * dimensions.$2 * dimensions.$3;

  Layer? layerById(String id) {
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  static Design fromJson(Map<String, Object?> json) {
    final dims = json['dimensions'];
    if (dims is! Map) throw const FormatException('missing dimensions');
    final dx = dims['x'], dy = dims['y'], dz = dims['z'];
    if (dx is! int || dy is! int || dz is! int) {
      throw const FormatException('dimensions need int x/y/z');
    }
    final name = json['name'];
    final desc = json['description'];
    final palette = [
      for (final e in (json['palette'] as List? ?? const []))
        PaletteEntry.fromJson(Map<String, Object?>.from(e as Map)),
    ];
    final blocks = [
      for (final e in (json['blocks'] as List? ?? const []))
        BlockEntry.fromJson(Map<String, Object?>.from(e as Map)),
    ];
    final layers = [
      for (final e in (json['layers'] as List? ?? const []))
        Layer.fromJson(Map<String, Object?>.from(e as Map)),
    ];
    final rooms = [
      for (final e in (json['rooms'] as List? ?? const []))
        Room.fromJson(Map<String, Object?>.from(e as Map)),
    ];
    final meta = json['metadata'];
    return Design(
      name: name is String ? name : 'Untitled',
      description: desc is String ? desc : null,
      dimensions: (dx, dy, dz),
      palette: palette,
      blocks: blocks,
      layers: layers,
      rooms: rooms,
      metadata: meta is Map ? Map<String, Object?>.from(meta) : const {},
    );
  }

  /// Fast lookup for the viewer/painter; built lazily.
  Map<(int, int, int), int>? _byKey;
  int? paletteIndexAt(int x, int y, int z) {
    final map = _byKey ??= {
      for (final b in blocks) b.key: b.paletteIndex,
    };
    return map[(x, y, z)];
  }

  void invalidateCaches() => _byKey = null;

  Map<String, Object?> toJson() => {
        'format': kSchematicFormat,
        'schemaVersion': kSchemaVersion,
        'name': name,
        'targetEdition': 'bedrock',
        'dimensions': {'x': dimensions.$1, 'y': dimensions.$2, 'z': dimensions.$3},
        'palette': palette.map((e) => e.toJson()).toList(),
        'blocks': blocks.map((e) => e.toJson()).toList(),
        if (description != null) 'description': description,
        if (layers.isNotEmpty) 'layers': layers.map((e) => e.toJson()).toList(),
        if (rooms.isNotEmpty) 'rooms': rooms.map((e) => e.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  static const kSchematicFormat = 'schematic3d-build';
  static const kSchemaVersion = 1;
}
