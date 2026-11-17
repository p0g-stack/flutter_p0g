// Usage: dart run tool/third_party.dart [root [name...]]
import 'dart:io';

import 'package:patched_source/patched_source.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? '.' : args.first).absolute;
  final thirdParty = Directory(p.join(root.path, 'third_party'));
  final names = args.skip(1).toSet();
  final series = thirdParty.existsSync()
      ? thirdParty
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where((dir) => File(p.join(dir.path, 'PIN')).existsSync())
            .toList()
      : <Directory>[];
  final available = series.map((dir) => p.basename(dir.path)).toSet();
  final missing = names.difference(available);
  if (missing.isNotEmpty) {
    stderr.writeln('Missing third-party series: ${missing.join(', ')}');
    exitCode = 1;
    return;
  }
  series.sort((a, b) => a.path.compareTo(b.path));
  for (final dir in series) {
    final name = p.basename(dir.path);
    if (names.isNotEmpty && !names.contains(name)) continue;
    final pin = await readPatchPin(File(p.join(dir.path, 'PIN')));
    if (!pin.containsKey('package')) {
      throw FormatException('Missing package= in ${p.join(dir.path, 'PIN')}');
    }
    final packagePath = pin['package']!;
    final patchesDir = Directory(p.join(dir.path, 'patches'));
    final patches = patchesDir.existsSync()
        ? patchesDir
              .listSync(followLinks: false)
              .whereType<File>()
              .where((file) => p.extension(file.path) == '.patch')
              .toList()
        : <File>[];
    patches.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final cache = Directory(p.join(root.path, '.dart_tool', 'third_party'));
    final destination = Directory(
      p.join(cache.path, '$name-${pin['commit']!.substring(0, 12)}'),
    );
    final source = await materializePatchedSource(
      destination: destination,
      repository: pin['repo']!,
      commit: pin['commit']!,
      patches: patches,
    );
    final package = Directory(p.join(source.path, packagePath));
    if (!p.isWithin(source.path, package.path) &&
        !p.equals(source.path, package.path)) {
      throw FormatException('package= escapes ${dir.path}');
    }
    final pubspec = File(p.join(package.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw StateError('Incomplete patched package: ${pubspec.path}');
    }
    final manifest = loadYaml(await pubspec.readAsString());
    final packageName = manifest is YamlMap ? manifest['name'] : null;
    if (packageName is! String || packageName.isEmpty) {
      throw FormatException('Missing package name in ${pubspec.path}');
    }
    String relative(String path) =>
        p.posix.joinAll(p.split(p.relative(path, from: root.path)));
    final previous = <String>{};
    for (final old
        in cache.listSync(followLinks: false).whereType<Directory>()) {
      if (RegExp('^${RegExp.escape(name)}-[0-9a-f]{12}\$')
              .hasMatch(p.basename(old.path)) &&
          File(p.join(old.path, '.patched_source.json')).existsSync()) {
        previous.add(relative(p.join(old.path, packagePath)));
      }
    }
    await setManagedPubOverride(
      overrides: File(p.join(root.path, 'pubspec_overrides.yaml')),
      package: packageName,
      relativePath: relative(package.path),
      previousManagedPaths: previous,
    );
  }
}
