/// App-wide constants. Keep in sync with converter/constants.py and the
/// Bedrock add-on (`ui/lang.js`, block JSONs).
library;

/// Internal design format + schema (matches _spec pack + addon scripts).
const String kSchematicFormat = 'schematic3d-build';
const int kSchemaVersion = 1;

/// Supported Minecraft: Bedrock Edition version targeted by the add-on.
const String kTargetBedrockVersion = '26.40.5';
const List<int> kMcApiModuleVersion = [2, 10, 0];

/// Categories from the spec (AR labels; other languages via l10n keys).
const List<String> kCategoryKeys = [
  'palaces', // قصور
  'houses', // منازل
  'towers', // أبراج
  'bridges', // جسور
  'farms', // مزارع
  'decor', // ديكورات
  'industrial', // صناعي
  'other', // أخرى
];

const Map<String, String> kCategoryEmoji = {
  'palaces': '🏛️',
  'houses': '🏠',
  'towers': '🗼',
  'bridges': '🌉',
  'farms': '🌾',
  'decor': '🪴',
  'industrial': '⚙️',
  'other': '📦',
};

enum SortKey { name, size, blocks, date }

const Map<String, int> kSortField = {
  'name': 0, 'size': 1, 'blocks': 2, 'date': 3,
};

/// Viewer modes (spec §5: 3D preview + floor plan tab).
enum ViewMode { threeD, floorPlan }

/// Prompt asset per language (external-AI template — no in-app AI).
const String kPromptAssetPath = 'assets/prompts/design_prompt';

/// Assets
const String kCatalogAsset = 'assets/generated/block_catalog.json';
const String kTintVectorsAsset = 'assets/generated/tint_vectors.json';
const String kAddonTemplateAssetRoot = 'assets/addon_template';

/// DB
const int kDatabaseVersion = 1;
const String kDatabaseName = 'schematic3d.db';

/// Import guard rails (parity with converter Limits).
const int kMaxDimension = 512;
const int kMaxBlocks = 2000000;
const int kMaxPalette = 4096;
const int kMaxVolume = 16 * 1024 * 1024;

/// File extensions accepted on import.
const List<String> kImportExtensions = [
  'json', 'mcstructure', 'schem', 'schematic',
];
