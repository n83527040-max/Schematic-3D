import 'dart:convert';
import 'dart:io';

/// Shared helpers for app tests: locate repo-root fixtures.
Directory get repoRoot {
  var d = Directory.current;
  while (!File('${d.path}/app/pubspec.yaml').existsSync() &&
      d.path != d.parent.path) {
    d = d.parent;
  }
  if (File('${d.path}/app/pubspec.yaml').existsSync() &&
      d.path.endsWith('app')) {
    d = d.parent;
  }
  return d;
}

String fixture(String rel) => '${repoRoot.path}/$rel';

Map<String, Object?> readJsonFixture(String rel) =>
    jsonDecode(File(fixture(rel)).readAsStringSync()) as Map<String, Object?>;

List<Map<String, Object?>> brokenFixtureNames() => [
      for (final f in Directory(fixture('examples')).listSync())
        if (f is File && f.path.contains('broken-'))
          {'file': f.path, 'name': f.uri.pathSegments.last},
    ];
