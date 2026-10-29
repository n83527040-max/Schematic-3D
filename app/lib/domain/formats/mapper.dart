import '../model/design.dart';

/// Java→Bedrock palette mapping + ghost tint assignment.
/// Parity-tested against the Python converter and the add-on via shared
/// fixtures (assets/generated/tint_vectors.json).
class Mapper {
  Mapper(this.catalog);
  final BlockCatalogIface catalog;

  static const _facingDir = {
    'down': 0, 'up': 1, 'north': 2, 'south': 3, 'west': 4, 'east': 5,
  };

  MapResult mapJavaEntry(PaletteEntry entry) {
    final raw = entry.id;
    var name = raw.contains(':') ? raw.split(':').last : raw;
    if (raw.startsWith('bedrock:')) name = raw.substring('bedrock:'.length);
    final states = Map<String, Object>.from(entry.states);

    final family = catalog.javaFamily[name];
    if (family != null) {
      final pick = _familyVariant(states, name);
      if (pick != null && family.containsKey(pick)) {
        final target = family[pick]!;
        final rest = Map<String, Object>.from(states)
          ..removeWhere((k, v) => _familyStateKeys[name]?.contains(k) ?? false);
        final translated = _translateStates(rest);
        return MapResult(
            PaletteEntry(target, translated.$1),
            translated.$2.isEmpty ? MapAction.family : MapAction.stateChanged,
            translated.$2);
      }
      return MapResult(entry, MapAction.unsupported,
          const ['family variant could not be resolved']);
    }

    final translated = _translateStates(states);
    final renamed = catalog.javaToBedrock[name];
    if (renamed != null) {
      return MapResult(
          PaletteEntry(renamed, translated.$1),
          renamed == 'minecraft:$name'
              ? (translated.$2.isEmpty ? MapAction.pass : MapAction.stateChanged)
              : MapAction.renamed,
          translated.$2);
    }
    return MapResult(
        PaletteEntry('minecraft:$name', translated.$1),
        translated.$2.isEmpty ? MapAction.pass : MapAction.stateChanged,
        translated.$2);
  }

  static String? _familyVariant(Map<String, Object> states, String family) {
    Object? v;
    switch (family) {
      case 'planks':
        v = states['type'] ?? states['variant'];
        break;
      case 'log':
      case 'log2':
      case 'wood':
      case 'leaves':
      case 'leaves2':
      case 'fence':
        v = states['variant'] ?? states['wood_type'] ?? states['type'];
        break;
      default:
        v = states['color'];
    }
    return v is String ? v.toLowerCase() : null;
  }

  static const _familyStateKeys = {
    'planks': {'type', 'variant'},
    'log': {'wood_type', 'axis', 'variant'},
    'leaves': {'persistent_bit', 'update_bit', 'variant', 'distance', 'persistent'},
    'fence': {'variant', 'waterlogged'},
    'wood': {'axis', 'variant'},
    'leaves2': {'persistent_bit', 'update_bit', 'variant', 'distance'},
    'stained_glass': {'color'},
    'stained_hardened_clay': {'color'},
    'wool': {'color'},
    'carpet': {'color'},
    'concrete': {'color'},
    'concrete_powder': {'color'},
  };

  static (Map<String, Object>, List<String>) _translateStates(
      Map<String, Object> s) {
    final kept = <String, Object>{};
    final dropped = <String>[];
    s.forEach((k, v) {
      switch (k) {
        case 'facing':
          final lv = v is String ? v.toLowerCase() : v;
          if (lv is String && _facingDir.containsKey(lv)) {
            kept['facing_direction'] = _facingDir[lv]!;
          } else {
            dropped.add(k);
          }
        case 'axis':
          kept[k] = v;
        case 'half':
          kept['upper_block'] = v == 'top';
        case 'waterlogged':
          dropped.add(k); // Bedrock models waterlogging as co-located blocks
        default:
          if (v is bool || v is int || v is String) {
            kept[k] = v;
          } else {
            dropped.add(k);
          }
      }
    });
    return (kept, dropped);
  }

  /// Ghost tint assignment — exact behavioral port of the add-on
  /// `core/tint.js`. Parity is pinned by shared golden vectors.
  static String? ghostTintFor(String bedrockId) {
    final n = bedrockId.startsWith('minecraft:')
        ? bedrockId.substring('minecraft:'.length)
        : bedrockId;
    if (n == 'air' || n == 'structure_void') return null;
    final head = n.split('_').first;

    if (n.contains('glass')) return 'ghost_glass';
    if (n.contains('ice') || n.contains('snow')) return 'ghost_white';
    if (n == 'water' || n.contains('water')) return 'ghost_blue';
    if (RegExp(
            r'glowstone|shroomlight|torch|lantern|campfire|end_rod|beacon|candle|redstone_lamp|sea_lantern')
        .hasMatch(n)) {
      return 'ghost_glow';
    }
    if (RegExp(r'^(coal|blackstone|obsidian|basalt|black)').hasMatch(n)) {
      return 'ghost_black';
    }
    if (RegExp(r'red_|crimson|nether_brick|magma|brick_block').hasMatch(n) &&
        !n.startsWith('red_sand')) {
      return 'ghost_red';
    }
    if (RegExp(r'emerald|slime|moss|vine|kelp|seagrass|grass$').hasMatch(n)) {
      return 'ghost_green';
    }
    if (RegExp(r'lapis|diamond|blue').hasMatch(n)) return 'ghost_blue';
    if (RegExp(r'iron|gold|netherite|copper|raw_|chain|bars|anvil|hopper|pipe')
        .hasMatch(n)) {
      return 'ghost_metal';
    }
    if (RegExp(
            r'quartz|purpur|bone|end_stone|^calcite|^smooth_stone|concrete_powder$')
        .hasMatch(n)) {
      return head == 'white' ? 'ghost_white' : _tintFromColorWord(n) ?? 'ghost_white';
    }
    if (RegExp(
            r'^(stone|cobble|granite|diorite|andesite|deepslate|tuff|bricks|stone_bricks)')
        .hasMatch(n)) {
      return 'ghost_stone';
    }
    if (RegExp(r'sand|gravel|clay|terracotta|hay|sponge|wool_stem').hasMatch(n)) {
      return 'ghost_sand';
    }
    if (_woods.contains(head) && !_colorWords.containsKey(head)) {
      return n.contains('leaves') ? 'ghost_green' : 'ghost_wood';
    }
    if (RegExp(
            r'^(log|planks|wood|fence|door|trapdoor|ladder|sign|bookshelf|noteblock|jukebox|chest|barrel|composter)')
        .hasMatch(n)) {
      return 'ghost_wood';
    }
    final cw = _tintFromColorWord(n);
    if (cw != null) return cw;
    if (n.contains('concrete') || n.contains('wool') || n.contains('carpet') ||
        n.contains('terracotta')) {
      return 'ghost_gray';
    }
    return 'ghost_gray';
  }

  static const _woods = {
    'oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
    'cherry', 'bamboo', 'crimson', 'warped',
  };

  static const _colorWords = {
    'white': 'ghost_white',
    'orange': 'ghost_red',
    'magenta': 'ghost_blue',
    'light_blue': 'ghost_blue',
    'yellow': 'ghost_glow',
    'lime': 'ghost_green',
    'pink': 'ghost_red',
    'gray': 'ghost_gray',
    'light_gray': 'ghost_gray',
    'silver': 'ghost_gray',
    'cyan': 'ghost_blue',
    'purple': 'ghost_blue',
    'blue': 'ghost_blue',
    'brown': 'ghost_wood',
    'green': 'ghost_green',
    'red': 'ghost_red',
    'black': 'ghost_black',
  };

  static String? _tintFromColorWord(String n) {
    final head = n.split('_').first;
    if (head == 'white') {
      return n.contains('concrete_powder') ? 'ghost_sand' : 'ghost_white';
    }
    return _colorWords[head];
  }

  static String? ghostBlockId(String bedrockId) {
    final t = ghostTintFor(bedrockId);
    return t == null ? null : 's3d:$t';
  }
}

enum MapAction { pass, renamed, family, stateChanged, unsupported }

class MapResult {
  const MapResult(this.entry, this.action, [this.notes = const []]);
  final PaletteEntry entry;
  final MapAction action;
  final List<String> notes;
}

/// Minimal interface so the mapper does not hard-depend on asset loading in
/// tests.
abstract class BlockCatalogIface {
  Map<String, Map<String, String>> get javaFamily;
  Map<String, String> get javaToBedrock;

  static BlockCatalogIface fromData({
    Map<String, Map<String, String>> javaFamily = const {},
    Map<String, String> javaToBedrock = const {},
  }) =>
      _Cat(javaFamily, javaToBedrock);
}

class _Cat implements BlockCatalogIface {
  _Cat(this.javaFamily, this.javaToBedrock);
  @override
  final Map<String, Map<String, String>> javaFamily;
  @override
  final Map<String, String> javaToBedrock;
}
