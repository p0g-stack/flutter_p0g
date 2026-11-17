import 'dart:io';

import 'package:mason/mason.dart';

/// The app name of the p0g_app workspace in the current directory, from
/// `core/pubspec.yaml` (`name: <app>_core`), or null.
String? appName() {
  final pubspec = File('core/pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  final m = RegExp(
    r'^name:\s*(\w+)_core\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  return m?.group(1);
}

/// One line the brick inserts above the `// p0g:<slot>` marker in [path].
final class Insertion {
  const Insertion(this.path, this.slot, this.line);
  final String path;
  final String slot;
  final String line;
}

/// Every insertion the service [name] needs in the workspace of [app]; the
/// panel's only with [panel].
List<Insertion> insertions(String app, String name, {required bool panel}) {
  final snake = name.snakeCase;
  final pascal = name.pascalCase;
  const runner = 'cli/lib/src/runner.dart';
  const panels = 'app/lib/panels/panels.dart';
  return [
    Insertion(
      'core/lib/${app}_core.dart',
      'exports',
      "export 'src/service/${snake}_service.dart';",
    ),
    Insertion(runner, 'imports', "import 'commands/${snake}_command.dart';"),
    Insertion(runner, 'commands', 'addCommand(${pascal}Command());'),
    Insertion(
      'cli/lib/src/commands/serve_command.dart',
      'services',
      "'$snake': withLogs(${pascal}ServiceWorker()),",
    ),
    if (panel) ...[
      Insertion(panels, 'imports', "import '${snake}_panel.dart';"),
      Insertion(panels, 'panels', '${pascal}Panel.inPlace,'),
    ],
  ];
}

/// Why [insertion] cannot be applied, or null when it can (or already was).
String? problem(Insertion insertion) {
  final file = File(insertion.path);
  if (!file.existsSync()) return '${insertion.path} is missing';
  final lines = file.readAsLinesSync();
  if (lines.any((l) => l.trim() == insertion.line.trim())) return null;
  if (_marker(lines, insertion.slot) < 0) {
    return '${insertion.path} has no // p0g:${insertion.slot} marker';
  }
  return null;
}

int _marker(List<String> lines, String slot) =>
    lines.indexWhere((l) => l.trimLeft().startsWith('// p0g:$slot'));

/// Inserts the line above its `// p0g:<slot>` marker, with the marker's
/// indentation, unless the file already has it. Returns whether the file
/// changed. pre_gen checked it with [problem] before anything was written.
bool insertAtMarker(Insertion insertion) {
  final file = File(insertion.path);
  final lines = file.readAsLinesSync();
  final line = insertion.line.trim();
  if (lines.any((l) => l.trim() == line)) return false;
  final i = _marker(lines, insertion.slot);
  if (i < 0) {
    throw StateError(
      '${insertion.path} lost its // p0g:${insertion.slot} marker after pre_gen',
    );
  }
  final marker = lines[i];
  final indent = marker.substring(0, marker.length - marker.trimLeft().length);
  // Above the marker, after the last line of the block it closes, so
  // `dart format` keeps the inserted line inside that block.
  var at = i;
  while (at > 0 && lines[at - 1].trim().isEmpty) {
    at--;
  }
  lines.insert(at, '$indent$line');
  file.writeAsStringSync('${lines.join('\n')}\n');
  return true;
}

/// Formats [paths] with `dart format`, if dart is on PATH.
void format(Logger logger, Iterable<String> paths) {
  final existing = paths.where((p) => File(p).existsSync()).toList();
  if (existing.isEmpty) return;
  try {
    Process.runSync('dart', ['format', ...existing]);
  } on ProcessException {
    logger.warn('dart is not on PATH; run dart format yourself.');
  }
}
