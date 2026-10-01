import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import '../p0g_cache.dart';

/// flutter_rust_bridge, pinned. The patch series in `patches/frb/` is made
/// against this commit (master after v2.14.0-beta.2; the patches do not
/// apply to the tag itself).
const kFrbRepo = 'https://github.com/fzyzcjy/flutter_rust_bridge';
const kFrbCommit = '848e438c561491adcc16cbf8b33bb61e541bd475';

/// frb's own marker for an app that uses it.
const kFrbConfigFile = 'flutter_rust_bridge.yaml';

bool usesFrb(Directory project) => project.childFile(kFrbConfigFile).existsSync();

Directory frbCacheDir() => p0gCacheDir().childDirectory('frb');
Directory frbSourceDir() => frbCacheDir().childDirectory('src');
File frbCodegenBinary() =>
    frbCacheDir().childDirectory('bin').childFile('flutter_rust_bridge_codegen');

/// Patch files in apply order.
List<File> frbPatches(Directory toolRoot) {
  final dir = toolRoot.childDirectory('patches').childDirectory('frb');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.patch')).toList()
    ..sort((a, b) => a.basename.compareTo(b.basename));
  return files;
}

/// Identifies one patched tree: the commit plus every patch's bytes.
String frbStamp(String commit, List<List<int>> patches) {
  final all = <int>[...commit.codeUnits];
  for (final bytes in patches) {
    all.addAll(sha256.convert(bytes).bytes);
  }
  return '$commit ${sha256.convert(all)}';
}

/// The app's `flutter_rust_bridge` Dart package must be the patched one,
/// because `build-web` runs that package's `build_web` entrypoint. Returns
/// why not, or null.
String? checkPatchedDartSide(PackageConfig config, String patchedFrbDart) {
  final pkg = config['flutter_rust_bridge'];
  if (pkg == null) return 'the app does not depend on flutter_rust_bridge';
  final root = p.normalize(pkg.root.toFilePath());
  if (p.equals(root, p.normalize(patchedFrbDart)) || p.isWithin(patchedFrbDart, root)) return null;
  return 'flutter_rust_bridge resolves to $root, not the patched copy.\n'
      'Add to the app pubspec and run pub get:\n'
      'dependency_overrides:\n'
      '  flutter_rust_bridge:\n'
      '    path: $patchedFrbDart';
}

/// Fetches frb at [kFrbCommit], applies the series and builds the codegen
/// into the cache. Skips work whose stamp already matches.
Future<void> precacheFrb() async {
  final toolRoot = await toolPackageRoot();
  final patches = frbPatches(toolRoot);
  final stamp = frbStamp(kFrbCommit, [for (final f in patches) f.readAsBytesSync()]);
  final stampFile = frbCacheDir().childFile('stamp');
  if (stampFile.existsSync() &&
      stampFile.readAsStringSync() == stamp &&
      frbCodegenBinary().existsSync()) {
    globals.printStatus(
      'frb ${kFrbCommit.substring(0, 7)} + ${patches.length} patch(es): up to date.',
    );
    return;
  }
  final src = frbSourceDir();
  if (src.existsSync()) src.deleteSync(recursive: true);
  src.createSync(recursive: true);
  Future<void> git(List<String> args) => _run(['git', ...args], src.path);
  await git(['init', '-q']);
  await git(['remote', 'add', 'origin', kFrbRepo]);
  await git(['fetch', '-q', '--depth', '1', 'origin', kFrbCommit]);
  await git(['checkout', '-q', 'FETCH_HEAD']);
  for (final patch in patches) {
    globals.printStatus('Applying ${patch.basename}');
    await git(['apply', patch.path]);
  }
  globals.printStatus('Building flutter_rust_bridge_codegen (cargo)...');
  await _run([
    'cargo', 'install', '--locked', '--path', 'frb_codegen', '--root', frbCacheDir().path, //
  ], src.path);
  stampFile.writeAsStringSync(stamp);
}

/// `build-web --no-threads` (patch 0001): single-threaded wasm that runs
/// without cross-origin isolation, which no manager provides.
Future<void> frbBuildWeb(Directory project, {required bool release}) async {
  if (!frbCodegenBinary().existsSync()) {
    throwToolExit('The patched frb is not built. Run `flutter_p0g precache --frb`.');
  }
  final config = await findPackageConfig(io.Directory(project.path));
  if (config == null) throwToolExit('Run `flutter pub get` first.');
  final problem = checkPatchedDartSide(config, frbSourceDir().childDirectory('frb_dart').path);
  if (problem != null) throwToolExit(problem);
  await _run([
    frbCodegenBinary().path, 'build-web', '--no-threads', if (release) '--release', //
  ], project.path);
}

Future<void> _run(List<String> cmd, String cwd) async {
  final code = await globals.processUtils.stream(cmd, workingDirectory: cwd);
  if (code != 0) throwToolExit('${cmd.take(2).join(' ')} failed (exit $code).', exitCode: code);
}
