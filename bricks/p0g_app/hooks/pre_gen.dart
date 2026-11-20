import 'package:mason/mason.dart';

void run(HookContext context) {
  // Direct dependencies of the generated workspace and their p0g siblings.
  const siblings = {
    'squadron_process': ['patched_source'],
    'flutter_webui_client': ['flutter_webui_root'],
    'flutter_webui_root': <String>[],
    'patched_source': <String>[],
  };
  final declarations = {
    for (final name in siblings.keys)
      name:
          '''  $name:
    git:
      url: https://github.com/p0g-stack/p0g
      path: pkgs/$name
      tag_pattern: p0g-v{{version}}
    version: ^0.9.0''',
  };
  final directSiblings = siblings.values.expand((deps) => deps).toSet();
  context.vars = {
    ...context.vars,
    for (final entry in declarations.entries) '${entry.key}_dep': entry.value,
    'sibling_overrides': declarations.entries
        .where((entry) => directSiblings.contains(entry.key))
        .map((entry) => entry.value)
        .join('\n'),
  };
}
