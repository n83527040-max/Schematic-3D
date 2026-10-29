import 'dart:convert';

import '../model/design.dart';

/// Canonical schematic3d-build JSON export with the conversion audit block —
/// port of converter exporters/json_out.py. This JSON is the design's
/// backup and its AI-review payload (spec §9).
Map<String, Object?> exportDesignJson(Design design,
    {Map<String, Object?>? conversion}) {
  final doc = design.toJson();
  if (conversion != null) doc['conversion'] = conversion;
  return doc;
}

String encodeDesignJson(Design design,
        {Map<String, Object?>? conversion, bool pretty = true}) =>
    (pretty
            ? const JsonEncoder.withIndent('  ')
            : const JsonEncoder())
        .convert(exportDesignJson(design, conversion: conversion));
