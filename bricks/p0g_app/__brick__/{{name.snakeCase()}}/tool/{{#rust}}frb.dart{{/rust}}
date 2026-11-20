// Prepares the portable Pub override from flutter_p0g's verified FRB cache.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:patched_source/patched_source.dart';
import 'package:path/path.dart' as p;

const _commit = '1e4df906b6d0e96aefbfa40dde5fa2833d417c1a';
const _repository = 'https://github.com/fzyzcjy/flutter_rust_bridge';

Future<String> _git(Directory dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir.path);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} in ${dir.path}: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<Map<String, dynamic>> _verify(Directory source) async {
  final stamp = File(p.join(source.path, '.patched_source.json'));
  final data = jsonDecode(await stamp.readAsString()) as Map<String, dynamic>;
  if (data['schema'] != 1 ||
      data['repository'] != _repository ||
      data['commit'] != _commit ||
      data['patchedTree'] is! String) {
    throw StateError('Wrong patched FRB identity: ${stamp.path}');
  }
  await _git(source, [
    'diff',
    '--exit-code',
    data['patchedTree'] as String,
    '--',
  ]);
  final extras =
      (await _git(source, ['ls-files', '--others', '--exclude-standard']))
          .split('\n')
          .where((name) => name.isNotEmpty && name != '.patched_source.json');
  if (extras.isNotEmpty) {
    throw StateError('Unowned files in ${source.path}: ${extras.join(', ')}');
  }
  for (final file in ['frb_dart/pubspec.yaml', 'frb_rust/Cargo.toml']) {
    if (!File(p.join(source.path, file)).existsSync()) {
      throw StateError(
        'Incomplete patched FRB source: ${p.join(source.path, file)}',
      );
    }
  }
  return data;
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/frb.dart <flutter_p0g FRB cache>');
    exitCode = 64;
    return;
  }
  final cache = Directory(args.single).absolute;
  final source = Directory(p.join(cache.path, 'src'));
  final data = await _verify(source);
  final sourceStamp = File(p.join(source.path, '.patched_source.json'));
  final identity =
      '$_commit ${sha256.convert([..._commit.codeUnits, ...sha256.convert(await sourceStamp.readAsBytes()).bytes])}';
  final binary = File(p.join(cache.path, 'bin', 'flutter_rust_bridge_codegen'));
  final binaryStamp = File(p.join(cache.path, 'stamp'));
  if (!binary.existsSync() ||
      !binaryStamp.existsSync() ||
      await binaryStamp.readAsString() != identity) {
    throw StateError(
      'Missing or stale patched FRB codegen in ${cache.path}; '
      'run flutter_p0g precache --frb --no-webui',
    );
  }
  final local = Directory(p.join('.dart_tool', 'p0g'))
    ..createSync(recursive: true);
  final path = p.join(local.path, 'frb');
  final owner = File(p.join(local.path, 'frb.owner.json'));
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  final target = await source.resolveSymbolicLinks();
  Map<String, dynamic>? owned;
  if (owner.existsSync()) {
    owned = jsonDecode(await owner.readAsString()) as Map<String, dynamic>;
  }
  if (type == FileSystemEntityType.link) {
    final link = Link(path);
    if (owned?['target'] != await link.target()) {
      throw StateError('Unowned FRB link: $path');
    }
    if (await link.target() != target) await link.update(target);
  } else if (type == FileSystemEntityType.directory) {
    if (owned?['materialized'] != true) {
      throw StateError('Unowned FRB directory: $path');
    }
    final previous = await _verify(Directory(path));
    if (previous['patchedTree'] != data['patchedTree']) {
      throw StateError(
        'Materialized FRB differs at $path; preserve it before replacing',
      );
    }
  } else if (type != FileSystemEntityType.notFound) {
    throw StateError('Unowned FRB path: $path');
  } else {
    try {
      await Link(path).create(target);
    } on FileSystemException {
      // On hosts without directory symlinks, install the same verified tree.
      final stage = await local.createTemp('frb-stage-');
      try {
        await _git(stage, [
          'clone',
          '--no-hardlinks',
          '--no-checkout',
          target,
          '.',
        ]);
        await _git(stage, [
          'read-tree',
          '--reset',
          '-u',
          data['patchedTree'] as String,
        ]);
        await sourceStamp.copy(p.join(stage.path, '.patched_source.json'));
        await _verify(stage);
        await stage.rename(path);
      } finally {
        if (stage.existsSync()) await stage.delete(recursive: true);
      }
    }
  }
  await owner.writeAsString(
    jsonEncode(
      FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.link
          ? {'target': target}
          : {'materialized': true},
    ),
  );
  await setManagedPubOverride(
    overrides: File('pubspec_overrides.yaml'),
    package: 'flutter_rust_bridge',
    relativePath: '.dart_tool/p0g/frb/frb_dart',
    previousManagedPaths: const {},
  );
  final cargo = Directory(p.join('rust', '.cargo'))
    ..createSync(recursive: true);
  await File(p.join(cargo.path, '.gitignore')).writeAsString('*\n');
  await File(p.join(cargo.path, 'config.toml')).writeAsString(
    '# Written by tool/frb.dart from the verified patched source.\n'
    '[patch.crates-io]\n'
    'flutter_rust_bridge = { path = ${jsonEncode(p.join(target, 'frb_rust'))} }\n',
  );
}
