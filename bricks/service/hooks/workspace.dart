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

/// Inserts [line] above the `// p0g:<slot>` marker in [path], with the
/// marker's indentation, unless the file already has it. Returns whether
/// the file changed.
bool insertAtMarker(Logger logger, String path, String slot, String line) {
  final file = File(path);
  if (!file.existsSync()) {
    logger.warn('$path is missing; add by hand: $line');
    return false;
  }
  final lines = file.readAsLinesSync();
  if (lines.any((l) => l.trim() == line.trim())) return false;
  final i = lines.indexWhere((l) => l.trimLeft().startsWith('// p0g:$slot'));
  if (i < 0) {
    logger.warn('$path has no // p0g:$slot marker; add by hand: $line');
    return false;
  }
  final marker = lines[i];
  final indent = marker.substring(0, marker.length - marker.trimLeft().length);
  // Above the marker, after the last line of the block it closes, so
  // `dart format` keeps the inserted line inside that block.
  var at = i;
  while (at > 0 && lines[at - 1].trim().isEmpty) {
    at--;
  }
  lines.insert(at, '$indent${line.trim()}');
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
