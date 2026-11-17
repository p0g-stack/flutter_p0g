import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';

const kitIdentityFile = '.kit-identity.json';
final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// Validates an archive digest before any file or network access.
String requireKitSha256(String? value) {
  if (value == null || !_sha256Pattern.hasMatch(value)) {
    throwToolExit('A kit requires a sha256 of exactly 64 hexadecimal characters.');
  }
  return value.toLowerCase();
}

/// Reads a complete installation identity, never trusting legacy caches.
Map<String, dynamic>? readKitIdentity(Directory directory) {
  final file = directory.childFile(kitIdentityFile);
  if (!file.existsSync()) return null;
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map<String, dynamic> ||
        value['schema'] != 1 ||
        value['sha256'] is! String ||
        !_sha256Pattern.hasMatch(value['sha256'] as String)) {
      return null;
    }
    return value;
  } on FormatException {
    return null;
  }
}

/// Builds a sibling tree and preserves the previous installation on failure.
void installKitStaged(
  Directory destination,
  Map<String, Object> identity,
  void Function(Directory stage) populate,
) {
  destination.parent.createSync(recursive: true);
  final stage = destination.parent.createTempSync('.kit-stage-');
  Directory? backup;
  var installed = false;
  try {
    populate(stage);
    stage.childFile(kitIdentityFile).writeAsStringSync(jsonEncode({'schema': 1, ...identity}));
    if (destination.existsSync()) {
      backup = destination.parent.createTempSync('.kit-previous-');
      destination.renameSync(backup.childDirectory('kit').path);
    }
    try {
      stage.renameSync(destination.path);
      installed = true;
    } catch (_) {
      if (backup != null) backup.childDirectory('kit').renameSync(destination.path);
      rethrow;
    }
  } finally {
    if (!installed && stage.existsSync()) stage.deleteSync(recursive: true);
    if (backup != null && (installed || !backup.childDirectory('kit').existsSync())) {
      backup.deleteSync(recursive: true);
    }
  }
}

/// Resolves an archive member without allowing it to escape the staged tree.
File kitMemberFile(Directory directory, String name) {
  final paths = directory.fileSystem.path;
  final out = directory.childFile(name);
  if (name.contains('\\') || !paths.isWithin(directory.path, out.path)) {
    throwToolExit('Kit archive member escapes its destination: $name.');
  }
  return out;
}
