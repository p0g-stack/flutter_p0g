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
/// - `gen_snapshot`: runs on the host, emits Android AOT ELF for the ABI.
/// - `dartaotruntime`: runs on the device (bionic), loads that ELF.
///
/// The kernel step uses the Flutter SDK's own `gen_kernel` and product
/// platform, which already accept `--target-os android`.

/// Android ABIs a kit can be built for, with Dart's `--arch` name.
const kDartArchForAbi = {'arm64-v8a': 'arm64', 'x86_64': 'x64'};

/// The default device ABI.
const kDefaultAbi = 'arm64-v8a';

class DartAndroidKit {
  DartAndroidKit(this.dir);

  final Directory dir;

  File get genSnapshot => dir.childFile('gen_snapshot');
  File get runtime => dir.childFile('dartaotruntime');
  File get versionFile => dir.childFile('VERSION');

  bool get isComplete =>
      genSnapshot.existsSync() && runtime.existsSync() && versionFile.existsSync();

  static Directory rootFor(String dartVersion) =>
      p0gCacheDir().childDirectory('dart-android').childDirectory(dartVersion);

  static DartAndroidKit forAbi(String dartVersion, String abi) =>
      DartAndroidKit(rootFor(dartVersion).childDirectory(abi));

  /// Kits installed for [dartVersion], by ABI.
  static Map<String, DartAndroidKit> installed(String dartVersion) => {
    for (final abi in kDartArchForAbi.keys)
      if (DartAndroidKit.forAbi(dartVersion, abi).isComplete)
        abi: DartAndroidKit.forAbi(dartVersion, abi),
  };
}

/// The Dart release inside the pinned Flutter.
String sdkDartVersion() => globals.fs
    .file(globals.fs.path.join(Cache.flutterRoot!, 'bin', 'cache', 'dart-sdk', 'version'))
    .readAsStringSync()
    .trim();

/// Where `precache --dart-android` looks when no kit is given: this repo's
/// release for the Dart version, built by .github/workflows/dart-android-kit.yml.
String defaultKitUrl(String dartVersion, String abi) =>
    'https://github.com/p0g-stack/flutter_p0g/releases/download/dart-android-$dartVersion/'
    'dart-android-$abi-$dartVersion.tar.gz';

/// A kit's ABI: its `ABI` member, else arm64-v8a (the first kits had none).
@visibleForTesting
String kitAbi(Archive archive) {
  final f = archive.findFile('ABI');
  return f == null ? kDefaultAbi : String.fromCharCodes(f.content as List<int>).trim();
}

/// Checks a kit archive's members before anything is written.
@visibleForTesting
String? validateKitArchive(Archive archive, String dartVersion) {
  final names = {for (final f in archive.files.where((f) => f.isFile)) f.name};
  for (final need in ['VERSION', 'gen_snapshot', 'dartaotruntime']) {
    if (!names.contains(need)) return 'kit lacks $need';
  }
  if (!kDartArchForAbi.containsKey(kitAbi(archive))) return 'unknown ABI ${kitAbi(archive)}';
  final version = String.fromCharCodes(archive.findFile('VERSION')!.content as List<int>).trim();
  if (version != dartVersion) {
    return 'kit is for Dart $version, but this Flutter carries Dart $dartVersion; '
        'snapshots only load in the runtime of their own version';
  }
  return null;
}

/// Installs the kit from a local `.tar.gz` or an https URL, checking
/// [sha256Hex] when given.
/// Without [source], fetches the release kit for [abi].
Future<void> precacheDartAndroid({
  String? source,
  String? sha256Hex,
  String abi = kDefaultAbi,
}) async {
  final version = sdkDartVersion();
  if (source == null && DartAndroidKit.forAbi(version, abi).isComplete) {
    globals.printStatus('Dart $version Android kit ($abi): up to date.');
    return;
  }
  source ??= defaultKitUrl(version, abi);
  final bytes = await fetchBytes(source);
  final digest = sha256.convert(bytes).toString();
  if (sha256Hex != null && sha256Hex != digest) {
    throwToolExit('Kit sha256 is $digest, expected $sha256Hex.');
  }
  final archive = decodeTarGz(bytes);
  final problem = validateKitArchive(archive, version);
  if (problem != null) throwToolExit('Dart Android kit: $problem.');
  final kit = DartAndroidKit.forAbi(version, kitAbi(archive));
  if (kit.dir.existsSync()) kit.dir.deleteSync(recursive: true);
  kit.dir.createSync(recursive: true);
  for (final f in archive.files.where((f) => f.isFile)) {
    final out = kit.dir.childFile(f.name)..writeAsBytesSync(f.content as List<int>);
    if (f.name != 'VERSION' && f.name != 'ABI') globals.os.chmod(out, '755');
  }
  globals.printStatus('Dart $version Android kit (${kitAbi(archive)}) installed (sha256 $digest).');
}

/// The module's `bin/<name>`: starts the snapshot for the device's ABI
/// (`bin/<abi>/<name>.aot`) with that ABI's runtime.
@visibleForTesting
String launcherScript(String name) =>
    '''
#!/system/bin/sh
# $name: Dart AOT snapshot on the bundled Android runtime (flutter_p0g).
b=\$(cd "\${0%/*}" && pwd)
d=\$b/\$(getprop ro.product.cpu.abi)
# Root shells may start with an empty environment; the VM needs a TMPDIR.
# The module's temp directory, as the root channel sets it.
m=\${b%/*}
export TMPDIR="\${TMPDIR:-/data/adb/\${m##*/}/tmp}"
mkdir -p "\$TMPDIR"
exec "\$d/dartaotruntime" "\$d/$name.aot" "\$@"
''';

/// Compiles [cli] to Android AOT once per kit (ABI); returns the module
/// files: the launcher, and `bin/<abi>/{<name>.aot,dartaotruntime}` each.
Future<Map<String, List<int>>> compileCliAot(
  CliPackage cli,
  Map<String, DartAndroidKit> kits,
  Directory work,
) async {
  final packages = cli.dir.childDirectory('.dart_tool').childFile('package_config.json');
  final workspacePackages = cli.dir.parent
      .childDirectory('.dart_tool')
      .childFile('package_config.json');
  final config = packages.existsSync() ? packages : workspacePackages;
  if (!config.existsSync()) throwToolExit('Run `dart pub get` in ${cli.dir.path} first.');
  final aots = await compileAndroidAot(
    entrypoint: cli.entrypoint,
    packageConfig: config,
    name: cli.name,
    kits: kits,
    work: work,
  );
  final files = <String, List<int>>{'bin/${cli.name}': launcherScript(cli.name).codeUnits};
  for (final MapEntry(key: abi, value: aot) in aots.entries) {
    files['bin/$abi/${cli.name}.aot'] = aot.readAsBytesSync();
    files['bin/$abi/dartaotruntime'] = kits[abi]!.runtime.readAsBytesSync();
  }
  return files;
}

/// Compiles [entrypoint] (resolved with [packageConfig]) to an Android AOT
/// snapshot per kit: `<work>/<abi>/<name>.aot`.
Future<Map<String, File>> compileAndroidAot({
  required File entrypoint,
  required File packageConfig,
  required String name,
  required Map<String, DartAndroidKit> kits,
  required Directory work,
}) async {
  if (kits.isEmpty) {
    throwToolExit('$name needs the Dart Android kit. Run `flutter_p0g precache --dart-android`.');
  }
  final fs = globals.fs;
  final sdk = fs.path.join(Cache.flutterRoot!, 'bin', 'cache', 'dart-sdk');
  work.createSync(recursive: true);
  final dill = work.childFile('$name.dill');

  Future<void> run(List<String> cmd) async {
    final r = await globals.processUtils.run(cmd, workingDirectory: entrypoint.parent.path);
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
    packageConfig.path,
    '-o',
    dill.path,
    entrypoint.path,
  ]);
  // The kernel is the same for every ABI; only gen_snapshot differs.
  final out = <String, File>{};
  for (final MapEntry(key: abi, value: kit) in kits.entries) {
    final aot = work.childDirectory(abi).childFile('$name.aot')..parent.createSync();
    await run([
      kit.genSnapshot.path,
      '--snapshot_kind=app-aot-elf',
      '--elf=${aot.path}',
      dill.path,
    ]);
    out[abi] = aot;
  }
  return out;
}
