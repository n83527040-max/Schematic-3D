Minecraft building design prompt template — copied by the app

You are a Minecraft building designer and an expert at turning designs into block schematics. Design the following building:

**User description:** [user writes their description here]

- Edition: Minecraft Bedrock 26.40.5.
- Style: [fantasy / modern / medieval / other]
- Approximate dimensions: [X × Y × Z]
- Floors: [count]
- Rooms and details: [list]
- Preferred materials: [list]
- Extra constraints: [roof/towers/furniture/gardens/block budget]

## Required outputs
1. A clear voxel/Minecraft-style reference image.
2. Separate images from front, back, both sides, top, and interiors when needed.
3. Floor plans with dimensions.
4. A materials table.
5. A complete JSON file in the `schematic3d-build` format specifying every block, its coordinates and its states.
6. A verification report of dimensions, actual counts, and uncertain blocks.
7. If you cannot produce the full file, say so explicitly; never invent a download link and never call a sample "complete".

## JSON schema
{
  "format": "schematic3d-build",
  "schemaVersion": 1,
  "name": "building name",
  "description": "description",
  "targetEdition": "bedrock",
  "dimensions": {"x": 1, "y": 1, "z": 1},
  "palette": [{"id": "minecraft:stone", "states": {}}],
  "blocks": [{"x": 0, "y": 0, "z": 0, "paletteIndex": 0}],
  "layers": [{"id": "floor_1", "name": "Ground floor", "yMin": 0, "yMax": 0}],
  "rooms": [],
  "metadata": {"generator": "external-ai", "notes": [], "unsupportedFeatures": []}
}

The example shows the structure only, not a full building. It must be filled with every block. Every coordinate must be inside dimensions, every paletteIndex valid, and no duplicate coordinates without explanation. Use known Bedrock identifiers and write block states only when you are certain of them.

**Accuracy rules:** A 3D render is not build data. Do not claim the JSON is a ready .mcstructure; it is an intermediate file that needs validation and conversion. Keep images separate from the JSON. If a part is uncertain, state it instead of claiming full accuracy.
