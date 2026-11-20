// dart run squadron_process:squadron_patch [root]
// Materialize the carried series and update only a verified managed override.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:patched_source/patched_source.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1) {
    stderr.writeln('Usage: dart run squadron_process:squadron_patch [root]');
    exitCode = 64;
    return;
  }
  try {
    final root = args.isEmpty
        ? Directory.current
        : Directory(args.single).absolute;
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:squadron_process/squadron_process.dart'),
    );
    if (lib == null) {
      throw StateError('squadron_process is not a dependency here');
    }
    final series = Directory(
      p.normalize(
        p.join(
          File.fromUri(lib).parent.parent.path,
          '..',
          '..',
          'third_party',
          'squadron',
        ),
      ),
    );
    final pin = await readPatchPin(File(p.join(series.path, 'PIN')));
    final packagePath = pin['package'] ?? '';
    if (p.isAbsolute(packagePath) ||
        p.split(p.normalize(packagePath)).contains('..')) {
      throw StateError(
        '${series.path}/PIN: package must be inside the repository',
      );
    }
    final repository = pin['repo']!;
    final commit = pin['commit']!;
    final relative = p.posix.join(
      '.dart_tool',
      'third_party',
      'squadron-${commit.substring(0, 12)}',
    );
    final overrides = File(p.join(root.path, 'pubspec_overrides.yaml'));
    final previous = <String>{};
    if (await overrides.exists()) {
      final doc = loadYaml(await overrides.readAsString());
      final dependencies = doc is YamlMap ? doc['dependency_overrides'] : null;
      final entry = dependencies is YamlMap ? dependencies['squadron'] : null;
      final old = entry is YamlMap ? entry['path'] : null;
      if (old is String && old != relative) {
        final directory = Directory(p.join(root.path, old));
        if (RegExp(r'^\.dart_tool/third_party/squadron-[a-f0-9]{12}$')
            .hasMatch(old)) {
          final stamp = jsonDecode(
            await File(p.join(directory.path, '.patched_source.json'))
                .readAsString(),
          ) as Map;
          final oldCommit = stamp['commit'];
          if (stamp['schema'] != 1 ||
              stamp['repository'] != repository ||
              oldCommit is! String ||
              !RegExp(r'^[a-f0-9]{40}$').hasMatch(oldCommit) ||
              !old.endsWith(oldCommit.substring(0, 12))) {
            throw StateError(
              '${directory.path}: invalid managed Squadron identity',
            );
          }
          await _assertTree(
            directory,
            repository,
            oldCommit,
            stamp['patchedTree'] as String,
          );
          previous.add(old);
        }
      }
    }
    // Validate the override before fetching or installing anything, without
    // changing the real file until the source and package have been verified.
    final validation = await Directory.systemTemp.createTemp(
      'squadron-override-',
    );
    try {
      final copy = File(p.join(validation.path, 'pubspec_overrides.yaml'));
      if (await overrides.exists()) await overrides.copy(copy.path);
      await setManagedPubOverride(
        overrides: copy,
        package: 'squadron',
        relativePath: relative,
        previousManagedPaths: previous,
      );
    } finally {
      await validation.delete(recursive: true);
    }
    final patchDirectory = Directory(p.join(series.path, 'patches'));
    final patches = await patchDirectory.exists()
        ? await patchDirectory
              .list(followLinks: false)
              .where((f) => f is File)
              .cast<File>()
              .toList()
        : <File>[];
    final source = await materializePatchedSource(
      destination: Directory(p.join(root.path, relative)),
      repository: repository,
      commit: commit,
      patches: patches,
    );
    final manifest = File(p.join(source.path, packagePath, 'pubspec.yaml'));
    if (!await manifest.exists()) {
      throw StateError('${manifest.path}: missing Squadron package');
    }
    final pubspec = loadYaml(await manifest.readAsString());
    if (pubspec is! YamlMap ||
        pubspec['name'] != 'squadron' ||
        pubspec['version'] is! String) {
      throw StateError(
        '${manifest.path}: expected a versioned squadron package',
      );
    }
    await setManagedPubOverride(
      overrides: overrides,
      package: 'squadron',
      relativePath: p.posix.join(relative, packagePath),
      previousManagedPaths: previous,
    );
    stdout.writeln(
      'squadron ${pubspec['version']} ($commit) at ${source.path}',
    );
    stdout.writeln('updated ${overrides.path}; run dart pub get');
  } catch (error) {
    stderr.writeln('squadron_patch: $error');
    exitCode = 1;
  }
}

Future<void> _assertTree(
  Directory directory,
  String repository,
  String commit,
  String tree,
) async {
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      (await _git(directory, [
            'config',
            '--get',
            'remote.origin.url',
          ])).trim() !=
          repository ||
      (await _git(directory, ['rev-parse', 'HEAD'])).trim() != commit) {
    throw StateError(
      '${directory.path}: conflicting managed Squadron checkout',
    );
  }
  // A disposable index proves all nonignored working content without staging
  // or modifying the owner's index.
  final temp = await Directory.systemTemp.createTemp('squadron-index-');
  final environment = {'GIT_INDEX_FILE': p.join(temp.path, 'index')};
  try {
    await _git(directory, ['read-tree', 'HEAD'], environment: environment);
    await _git(directory, [
      'add',
      '-A',
      '--',
      '.',
      ':!.patched_source.json',
    ], environment: environment);
    final actual = (await _git(directory, [
      'write-tree',
    ], environment: environment)).trim();
    if (actual != tree) {
      throw StateError(
        '${directory.path}: source has user changes; refusing override update',
      );
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<String> _git(
  Directory directory,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run('git', [
    '-C',
    directory.path,
    ...args,
  ], environment: environment);
  if (result.exitCode != 0) {
    throw StateError(
      '${directory.path}: git ${args.join(' ')}: ${result.stderr}',
    );
  }
  return result.stdout as String;
}
