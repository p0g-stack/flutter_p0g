import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../p0g_cache.dart';

/// The app's Dart CLI (the bricks `cli/` package), which is also its WebUI
/// root process. Looked up in the app, then in the workspace root above it.
class CliPackage {
  CliPackage(this.dir, this.name, this.entrypoint);

  final Directory dir;

  /// Executable name inside the module's `bin/`.
  final String name;
  final File entrypoint;

  static CliPackage? find(Directory project) {
    for (final dir in [project.childDirectory('cli'), project.parent.childDirectory('cli')]) {
      final pubspec = dir.childFile('pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      return fromPubspec(dir, pubspec.readAsStringSync());
    }
    return null;
  }

  /// First `executables:` entry, else `bin/<package>.dart`, else the only
  /// file in `bin/`: the same order `dart pub global activate` uses.
  static CliPackage fromPubspec(Directory dir, String pubspecYaml) {
    final yaml = loadYaml(pubspecYaml) as YamlMap;
    final package = yaml['name'] as String;
    final bin = dir.childDirectory('bin');
    final executables = yaml['executables'];
    if (executables is YamlMap && executables.isNotEmpty) {
      final name = executables.keys.first as String;
      final script = (executables[name] as String?) ?? name;
      return CliPackage(dir, name, bin.childFile('$script.dart'));
    }
    final byName = bin.childFile('$package.dart');
    if (byName.existsSync()) return CliPackage(dir, package, byName);
    final scripts = bin.existsSync()
        ? bin.listSync().whereType<File>().where((f) => f.path.endsWith('.dart')).toList()
        : <File>[];
    if (scripts.length == 1) {
      return CliPackage(dir, p.basenameWithoutExtension(scripts.single.path), scripts.single);
    }
    throwToolExit('${dir.path}: cannot tell which bin/ script is the CLI; add `executables:`.');
  }
}

/// Compiles [cli] for the device into [outFile].
///
/// Android is the target: the module runs on bionic. Dart 3.13 cannot yet
/// cross-compile `exe` for android from this host (its Linux targets link
/// glibc), so this fails with that explanation until an Android Dart runtime
/// is available. See README, "The root process".
Future<void> compileCli(CliPackage cli, File outFile) async {
  outFile.parent.createSync(recursive: true);
  final result = await globals.processUtils.run([
    dartBinary(), 'compile', 'exe', '--target-os', 'android', '--target-arch', 'arm64', //
    '-o', outFile.path, cli.entrypoint.path,
  ], workingDirectory: cli.dir.path);
  if (result.exitCode == 0) return;
  if (result.toString().contains('Unsupported target platform android')) {
    throwToolExit(
      'cli/ needs an Android (bionic) Dart executable, and this Dart SDK cannot '
      'cross-compile one: `dart compile exe` only targets linux_* here, which '
      'links glibc and does not start on Android. Build without cli/ for now.',
    );
  }
  throwToolExit('dart compile exe failed:\n$result');
}

/// The frb native library the CLI loads, built per ABI with cargo-ndk.
/// Returns the `.so` files for each ABI.
Future<Map<String, List<File>>> buildRustForCli(
  Directory rustDir,
  Directory outDir,
  List<String> abis,
) async {
  final ndk = await globals.processUtils.run(['cargo', 'ndk', '--version']);
  if (ndk.exitCode != 0) {
    throwToolExit(
      'Building rust/ for the device needs cargo-ndk and the Android NDK '
      '(`cargo install cargo-ndk`, ANDROID_NDK_HOME).',
    );
  }
  final code = await globals.processUtils.stream([
    'cargo',
    'ndk',
    for (final abi in abis) ...['-t', abi],
    '-o',
    outDir.path,
    'build',
    '--release', //
  ], workingDirectory: rustDir.path);
  if (code != 0) throwToolExit('cargo ndk build failed (exit $code).');
  return {
    for (final abi in abis)
      abi: outDir.childDirectory(abi).existsSync()
          ? outDir
                .childDirectory(abi)
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.so'))
                .toList()
          : <File>[],
  };
}

/// rust/ built elsewhere (CI with the NDK): `<dir>/<abi>/*.so`, as
/// `cargo ndk -o <dir>` lays it out. Every ABI the root process ships for
/// needs its libraries.
Map<String, List<File>> prebuiltRustLibs(Directory dir, List<String> abis) => {
  for (final abi in abis)
    abi: switch (dir.childDirectory(abi)) {
      final d when d.existsSync() =>
        d.listSync().whereType<File>().where((f) => f.path.endsWith('.so')).toList()
          ..sort((a, b) => a.path.compareTo(b.path)),
      _ => throwToolExit('--device-rust-libs: no ${dir.childDirectory(abi).path}'),
    },
};
