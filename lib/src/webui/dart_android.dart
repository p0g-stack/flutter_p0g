import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import '../p0g_cache.dart';
import 'cli_exe.dart';

/// Running the app's Dart CLI on Android.
///
/// Stock Dart can't target Android from a desktop host (`dart compile exe`
/// and `aot-snapshot` reject `--target-os android`), and a snapshot only
/// loads in a runtime of the same Dart version, OS and build flags (its
/// features string reads e.g. `product ... arm64 android`). So the kit pairs
/// the two halves, both built from the pinned Dart release with
/// `tools/build.py --os android --arch arm64`:
///
/// - `gen_snapshot`: runs on the host, emits android-arm64 AOT ELF.
/// - `dartaotruntime`: runs on the device (bionic), loads that ELF.
///
/// The kernel step uses the Flutter SDK's own `gen_kernel` and product
/// platform, which already accept `--target-os android`.
/// The one ABI built today; the module layout is per ABI so more can follow.
const kAbi = 'arm64-v8a';

class DartAndroidKit {
  DartAndroidKit(this.dir);

  final Directory dir;

  File get genSnapshot => dir.childFile('gen_snapshot');
  File get runtime => dir.childFile('dartaotruntime');
  File get versionFile => dir.childFile('VERSION');

  bool get isComplete =>
      genSnapshot.existsSync() && runtime.existsSync() && versionFile.existsSync();

  static DartAndroidKit forVersion(String dartVersion) =>
      DartAndroidKit(p0gCacheDir().childDirectory('dart-android').childDirectory(dartVersion));
}

/// The Dart release inside the pinned Flutter.
String sdkDartVersion() => globals.fs
    .file(globals.fs.path.join(Cache.flutterRoot!, 'bin', 'cache', 'dart-sdk', 'version'))
    .readAsStringSync()
    .trim();

/// Where `precache --dart-android` looks when no kit is given: this repo's
/// release for the Dart version, built by .github/workflows/dart-android-kit.yml.
String defaultKitUrl(String dartVersion) =>
    'https://github.com/p0g-stack/flutter_p0g/releases/download/dart-android-$dartVersion/'
    'dart-android-arm64-$dartVersion.tar.gz';

/// Checks a kit archive's members before anything is written.
@visibleForTesting
String? validateKitArchive(Archive archive, String dartVersion) {
  final names = {for (final f in archive.files.where((f) => f.isFile)) f.name};
  for (final need in ['VERSION', 'gen_snapshot', 'dartaotruntime']) {
    if (!names.contains(need)) return 'kit lacks $need';
  }
  final version = String.fromCharCodes(archive.findFile('VERSION')!.content as List<int>).trim();
  if (version != dartVersion) {
    return 'kit is for Dart $version, but this Flutter carries Dart $dartVersion; '
        'snapshots only load in the runtime of their own version';
  }
  return null;
}

/// Installs the kit from a local `.tar.gz` or an https URL, checking
/// [sha256Hex] when given.
Future<void> precacheDartAndroid({String? source, String? sha256Hex}) async {
  final version = sdkDartVersion();
  final kit = DartAndroidKit.forVersion(version);
  if (kit.isComplete && source == null) {
    globals.printStatus('Dart $version Android kit: up to date.');
    return;
  }
  source ??= defaultKitUrl(version);
  final bytes = await fetchBytes(source);
  final digest = sha256.convert(bytes).toString();
  if (sha256Hex != null && sha256Hex != digest) {
    throwToolExit('Kit sha256 is $digest, expected $sha256Hex.');
  }
  final archive = decodeTarGz(bytes);
  final problem = validateKitArchive(archive, version);
  if (problem != null) throwToolExit('Dart Android kit: $problem.');
  if (kit.dir.existsSync()) kit.dir.deleteSync(recursive: true);
  kit.dir.createSync(recursive: true);
  for (final f in archive.files.where((f) => f.isFile)) {
    final out = kit.dir.childFile(f.name)..writeAsBytesSync(f.content as List<int>);
    if (f.name != 'VERSION') globals.os.chmod(out, '755');
  }
  globals.printStatus('Dart $version Android kit installed (sha256 $digest).');
}

/// The module's `bin/<name>`: starts the snapshot for the device's ABI
/// (`bin/<abi>/<name>.aot`) with that ABI's runtime.
@visibleForTesting
String launcherScript(String name) =>
    '''
#!/system/bin/sh
# $name: Dart AOT snapshot on the bundled Android runtime (flutter_p0g).
d=\${0%/*}/\$(getprop ro.product.cpu.abi)
exec "\$d/dartaotruntime" "\$d/$name.aot" "\$@"
''';

/// Compiles [cli] to android-arm64 AOT with [kit]; returns the module files.
Future<Map<String, List<int>>> compileCliAot(
  CliPackage cli,
  DartAndroidKit kit,
  Directory work,
) async {
  if (!kit.isComplete) {
    throwToolExit('cli/ needs the Dart Android kit. Run `flutter_p0g precache --dart-android`.');
  }
  final fs = globals.fs;
  final sdk = fs.path.join(Cache.flutterRoot!, 'bin', 'cache', 'dart-sdk');
  work.createSync(recursive: true);
  final dill = work.childFile('${cli.name}.dill');
  final aot = work.childFile('${cli.name}.aot');
  final packages = cli.dir.childDirectory('.dart_tool').childFile('package_config.json');
  final workspacePackages = cli.dir.parent
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  final config = packages.existsSync() ? packages : workspacePackages;
  if (!config.existsSync()) throwToolExit('Run `dart pub get` in ${cli.dir.path} first.');

  Future<void> run(List<String> cmd) async {
    final r = await globals.processUtils.run(cmd, workingDirectory: cli.dir.path);
    if (r.exitCode != 0) throwToolExit('${fs.path.basename(cmd.first)} failed:\n$r');
  }

  await run([
    fs.path.join(sdk, 'bin', 'dartaotruntime'),
    fs.path.join(sdk, 'bin', 'snapshots', 'gen_kernel_aot.dart.snapshot'),
    '--platform',
    fs.path.join(sdk, 'lib', '_internal', 'vm_platform_product.dill'),
    '--aot',
    '--target-os',
    'android',
    '-Ddart.vm.product=true',
    '--packages',
    config.path,
    '-o',
    dill.path,
    cli.entrypoint.path,
  ]);
  await run([kit.genSnapshot.path, '--snapshot_kind=app-aot-elf', '--elf=${aot.path}', dill.path]);
  return {
    'bin/${cli.name}': launcherScript(cli.name).codeUnits,
    'bin/$kAbi/${cli.name}.aot': aot.readAsBytesSync(),
    'bin/$kAbi/dartaotruntime': kit.runtime.readAsBytesSync(),
  };
}
