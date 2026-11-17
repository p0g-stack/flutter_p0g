import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const _stampName = '.patched_source.json';
final _pending = <String, Future<void>>{};
final _commitPattern = RegExp(r'^[0-9a-fA-F]{40}$');

Future<Map<String, String>> readPatchPin(File file) async {
  final pin = <String, String>{};
  for (final raw in await file.readAsLines()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final at = line.indexOf('=');
    if (at <= 0) throw FormatException('${file.path}: invalid PIN line: $line');
    final key = line.substring(0, at).trim();
    final value = line.substring(at + 1).trim();
    if (!const ['repo', 'commit', 'tag', 'package'].contains(key) ||
        pin.containsKey(key) || (value.isEmpty && key != 'package')) {
      throw FormatException('${file.path}: invalid or duplicate $key=');
    }
    pin[key] = value;
  }
  for (final key in const ['repo', 'commit']) {
    if (!pin.containsKey(key)) throw FormatException('${file.path}: missing $key=');
  }
  if (!_commitPattern.hasMatch(pin['commit']!)) {
    throw FormatException('${file.path}: commit must be a full 40-hex SHA');
  }
  return pin;
}

Future<void> setManagedPubOverride({
  required File overrides,
  required String package,
  required String relativePath,
  required Set<String> previousManagedPaths,
}) async {
  if (p.isAbsolute(relativePath)) {
    throw ArgumentError.value(relativePath, 'relativePath', 'must be relative');
  }
  final text = await overrides.exists() ? await overrides.readAsString() : '';
  Never conflict(Object detail) => throw StateError(
    '${overrides.path}: conflicting override for $package: $detail',
  );
  dynamic document;
  try {
    document = loadYaml(text);
  } on YamlException catch (error) {
    conflict(error);
  }
  if (document == null && text.split('\n').any(
      (line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))) {
    conflict('expected a YAML mapping');
  }
  if (document != null && document is! YamlMap) conflict('expected a YAML mapping');
  final dependencies = document?['dependency_overrides'];
  if (document != null && document.containsKey('dependency_overrides') &&
      dependencies is! YamlMap) {
    conflict('dependency_overrides must be a mapping');
  }
  if (dependencies is YamlMap && dependencies.containsKey(package)) {
    final current = dependencies[package];
    if (current is! YamlMap || current.length != 1 || current['path'] is! String) {
      conflict(current);
    }
    final path = current['path'] as String;
    if (path == relativePath) return;
    if (!previousManagedPaths.contains(path)) conflict(path);
  }
  final editor = YamlEditor(text);
  if (document == null) {
    editor.update([], {'dependency_overrides': {package: {'path': relativePath}}});
  } else if (dependencies == null) {
    editor.update(['dependency_overrides'], {package: {'path': relativePath}});
  } else {
    editor.update(['dependency_overrides', package], {'path': relativePath});
  }
  await overrides.writeAsString(editor.toString());
}

Future<Directory> materializePatchedSource({
  required Directory destination,
  required String repository,
  required String commit,
  required List<File> patches,
}) async {
  if (!_commitPattern.hasMatch(commit)) {
    throw ArgumentError.value(commit, 'commit', 'must be a full 40-hex SHA');
  }
  await destination.parent.create(recursive: true);
  final parent = await destination.parent.resolveSymbolicLinks();
  final target = Directory(p.join(parent, p.basename(destination.absolute.path)));
  // POSIX file locks are process-wide; queue same-isolate calls as well.
  final key = target.path;
  final previous = _pending[key];
  final done = Completer<void>();
  _pending[key] = done.future;
  try {
    if (previous != null) await previous;
    final lock = await File('$key.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await _materialize(target, repository, commit, patches);
    } finally {
      await lock.close();
    }
  } finally {
    done.complete();
    if (identical(_pending[key], done.future)) _pending.remove(key);
  }
}

Future<Directory> _materialize(Directory target, String repository,
    String commit, List<File> input) async {
  final patches = <File>[];
  for (final file in input) {
    if (p.extension(file.path) == '.patch' &&
        await FileSystemEntity.type(file.path, followLinks: false) == FileSystemEntityType.file) {
      patches.add(file);
    }
  }
  patches.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  final names = <String>{};
  final bytes = <List<int>>[];
  final identities = <Map<String, String>>[];
  for (final patch in patches) {
    final name = p.basename(patch.path);
    if (!names.add(name)) throw ArgumentError('Duplicate patch filename: $name');
    final data = await patch.readAsBytes();
    bytes.add(data);
    identities.add({'name': name, 'sha256': sha256.convert(data).toString()});
  }
  final identity = <String, dynamic>{
    'schema': 1, 'repository': repository, 'commit': commit, 'patches': identities,
  };
  final type = await FileSystemEntity.type(target.path, followLinks: false);
  if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.directory) {
    throw StateError('${target.path}: destination is not an owned directory');
  }
  final exists = type == FileSystemEntityType.directory;
  if (exists && !await target.list().isEmpty) {
    final stamp = File(p.join(target.path, _stampName));
    Map<String, dynamic> recorded;
    try {
      recorded = jsonDecode(await stamp.readAsString()) as Map<String, dynamic>;
      if (recorded['schema'] != 1 || recorded['repository'] is! String ||
          recorded['commit'] is! String || recorded['patches'] is! List ||
          recorded['patchedTree'] is! String ||
          !_commitPattern.hasMatch(recorded['patchedTree'] as String)) {
        throw const FormatException('invalid stamp');
      }
    } catch (error) {
      throw StateError('${target.path}: nonempty directory without a valid ownership stamp ($error)');
    }
    await _assertUnmodified(target, recorded['patchedTree'] as String);
    final oldIdentity = Map<String, dynamic>.of(recorded)..remove('patchedTree');
    if (jsonEncode(oldIdentity) == jsonEncode(identity)) return target;
  }
  final stage = await target.parent.createTemp('.${p.basename(target.path)}.staging-');
  Directory? backup;
  try {
    await _git(stage, ['init', '-q']);
    await _git(stage, ['remote', 'add', 'origin', repository]);
    await _git(stage, ['fetch', '-q', '--depth', '1', 'origin', commit]);
    await _git(stage, ['checkout', '-q', '--detach', commit]);
    for (final patch in bytes) {
      final process = await Process.start('git', ['-C', stage.path, 'apply', '--whitespace=nowarn', '-']);
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = utf8.decoder.bind(process.stderr).join();
      process.stdin.add(patch);
      await process.stdin.close();
      final code = await process.exitCode;
      await stdoutDone;
      final error = await stderrDone;
      if (code != 0) throw StateError('${target.path}: git apply failed: $error');
    }
    await _git(stage, ['add', '-A']);
    identity['patchedTree'] = (await _git(stage, ['write-tree'])).trim();
    await File(p.join(stage.path, _stampName)).writeAsString('${jsonEncode(identity)}\n', flush: true);
    if (exists) {
      // Recheck immediately before replacement, including edits during fetch.
      final stamp = File(p.join(target.path, _stampName));
      if (await stamp.exists()) {
        final recorded = jsonDecode(await stamp.readAsString()) as Map;
        await _assertUnmodified(target, recorded['patchedTree'] as String);
      } else if (!await target.list().isEmpty) {
        throw StateError('${target.path}: destination changed during materialization');
      }
      final reserved = await target.parent.createTemp('.${p.basename(target.path)}.previous-');
      await reserved.delete();
      backup = await target.rename(reserved.path);
    }
    try {
      await stage.rename(target.path);
    } catch (_) {
      if (backup != null) await backup.rename(target.path);
      rethrow;
    }
    if (backup != null) await backup.delete(recursive: true);
    return target;
  } finally {
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}

Future<void> _assertUnmodified(Directory directory, String tree) async {
  final diff = await Process.run('git', ['-C', directory.path, 'diff', '--quiet', tree, '--']);
  final untracked = (await _git(directory, ['ls-files', '--others', '--exclude-standard', '-z']))
      .split('\u0000').where((name) => name.isNotEmpty && name != _stampName);
  if (diff.exitCode != 0 || untracked.isNotEmpty) {
    throw StateError('${directory.path}: managed source has user changes; refusing replacement');
  }
}

Future<String> _git(Directory directory, List<String> args) async {
  final result = await Process.run('git', ['-C', directory.path, ...args]);
  if (result.exitCode != 0) {
    throw StateError('${directory.path}: git ${args.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}
