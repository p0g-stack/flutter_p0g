import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import '../apk/keystore.dart';
import '../apk/rename_apk.dart';
import '../apk/sign_v2.dart';
import '../apk/axml.dart';
import '../apk/zip_apk.dart';
import '../artifact_lock.dart';
import '../p0g_cache.dart';
import '../p0g_repository.dart';
import 'module.dart' show kAppPlaneApkPath;
import 'dart_android.dart';
import 'webui_packages.dart';

/// The package of the app plane's base APK, the webui-termux-api release
/// locked in `artifacts.lock.json` (`webuiTermuxApi`); each module's copy
/// renames it.
const kAppPlaneBasePackage = 'com.webui.termux.api';

/// [moduleId] as one Java package segment: characters outside
/// `[A-Za-z0-9_]` become `_`, and a leading digit gets an `m`.
String appPlaneSegment(String moduleId) {
  final seg = moduleId.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
  return seg.isEmpty || RegExp('^[0-9]').hasMatch(seg) ? 'm$seg' : seg;
}

/// The package of [moduleId]'s app plane APK, so Android's permission
/// dialog, grants and data belong to that module alone.
String appPlanePackageName(String moduleId) => 'com.webui.api.${appPlaneSegment(moduleId)}';

/// The base APK's versionCode (the per-module copy keeps it).
Future<int> appPlaneVersionCode() async {
  final apk = await appPlaneApk();
  final manifest = readZipEntries(apk.readAsBytesSync())
      .firstWhere((e) => e.name == 'AndroidManifest.xml');
  return manifestVersionCode(entryBytes(manifest)) ??
      throwToolExit('webui-termux-api ${apk.parent.basename} has no versionCode.');
}

/// The package that brings the app plane in.
const kAppPlanePackage = 'webui_app_plane';

/// The cached base APK, one directory per locked release tag.
Future<File> appPlaneApk() async => p0gCacheDir()
    .childDirectory('app-plane')
    .childDirectory((await artifactLock()).webuiTermuxApi.tag)
    .childFile('WebuiTermuxApi.apk');

/// Fetches the locked APK and checks its sha256. [source] replaces the
/// release URL (a path or URL; the lock's sha256 still applies).
Future<void> precacheAppPlane({String? source, bool force = false}) async {
  final release = (await artifactLock()).webuiTermuxApi;
  final apk = await appPlaneApk();
  if (!force && source == null && apk.existsSync()) return;
  final asset = release.single;
  final bytes = await fetchBytes(source ?? asset.url);
  final digest = sha256.convert(bytes).toString();
  if (digest != asset.sha256) {
    throwToolExit('webui-termux-api: sha256 is $digest, the lock says ${asset.sha256}.');
  }
  apk
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  globals.printStatus('webui-termux-api ${release.tag} installed (sha256 $digest).');
}

/// The app plane's module files (`pkgs/webui/docs/plugins.md`, "What
/// flutter_p0g ships"): the `termux-api` launcher, its snapshot per kit (run
/// by the root channel's runtime) and the module's own APK at
/// [kAppPlaneApkPath], renamed for [moduleId], labelled [title] and signed
/// with [key]. The module installs it as an ordinary app ([AppPlaneApp]).
Future<Map<String, List<int>>> appPlaneFiles(
  Map<String, DartAndroidKit> kits,
  Directory work, {
  required String moduleId,
  required String title,
  required ApkSigningKey key,
}) async {
  await precacheAppPlane();
  final pkg = webuiPackagesDir(await p0gRepository()).childDirectory(kAppPlanePackage);
  final aots = await compileAndroidAot(
    entrypoint: pkg.childDirectory('bin').childFile('webui_termux_api.dart'),
    packageConfig: webuiSourcesPackageConfig(),
    name: 'webui_termux_api',
    kits: kits,
    work: work,
  );
  final apk = renameApk(
    (await appPlaneApk()).readAsBytesSync(),
    from: kAppPlaneBasePackage,
    to: appPlanePackageName(moduleId),
    label: title,
    key: key,
  );
  return {
    'webui_app_plane/termux-api': pkg
        .childDirectory('module')
        .childFile('termux-api')
        .readAsBytesSync(),
    for (final MapEntry(key: abi, value: aot) in aots.entries)
      'webui_app_plane/$abi/webui_termux_api.aot': aot.readAsBytesSync(),
    kAppPlaneApkPath: apk,
  };
}

/// The key the app plane APK is signed with, as stock Flutter picks one for
/// an Android build: the release key from `android/key.properties` when there
/// is one, otherwise the debug key in `~/.android/debug.keystore`, made on
/// first use.
ApkSigningKey appPlaneSigningKey(Directory app) {
  final android = app.childDirectory('android');
  final props = android.childFile('key.properties');
  if (props.existsSync()) return _releaseKey(props, [android.childDirectory('app'), android]);
  return _debugKey();
}

ApkSigningKey _releaseKey(File props, List<Directory> bases) {
  final p = parseKeyProperties(props.readAsStringSync());
  String need(String k) => p[k] ?? throwToolExit('${props.path} has no $k.');
  final storeFile = need('storeFile');
  final fs = globals.fs;
  final candidates = fs.path.isAbsolute(storeFile)
      ? [fs.file(storeFile)]
      : [for (final b in bases) b.childFile(storeFile)];
  final store = candidates.firstWhere(
    (f) => f.existsSync(),
    orElse: () => throwToolExit(
      '${props.path}: storeFile $storeFile not found (looked in '
      '${candidates.map((f) => f.path).join(', ')}).',
    ),
  );
  try {
    final key = readPkcs12(
      store.readAsBytesSync(),
      storePassword: need('storePassword'),
      alias: p['keyAlias'],
      keyPassword: p['keyPassword'],
    );
    globals.printStatus('Signing the app plane APK with ${store.path} (${props.path}).');
    return key;
  } on FormatException catch (e) {
    throwToolExit('${store.path}: ${e.message}');
  }
}

ApkSigningKey _debugKey() {
  final env = globals.platform.environment;
  final fs = globals.fs;
  final androidHome =
      env['ANDROID_USER_HOME'] ?? fs.path.join(globals.fsUtils.homeDirPath ?? '.', '.android');
  final store = fs.directory(androidHome).childFile('debug.keystore');
  final key = _readOrMakeDebugKey(store);
  if (key != null) return key;
  // A JKS debug keystore from an old JDK: keep a PKCS12 one of our own.
  final own = p0gCacheDir().childFile('debug.keystore');
  globals.printStatus(
    '${store.path} is not a PKCS12 keystore; signing with ${own.path} instead. '
    'Modules built on another machine get a different key; configure '
    'android/key.properties for releases.',
  );
  return _readOrMakeDebugKey(own) ?? throwToolExit('${own.path} is unreadable.');
}

ApkSigningKey? _readOrMakeDebugKey(File store) {
  if (!store.existsSync()) {
    final key = generateSigningKey();
    store
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(writePkcs12(key, alias: kDebugKeyAlias, password: kDebugKeyPassword));
    globals.printStatus('Created the debug keystore ${store.path}.');
    return key;
  }
  try {
    return readPkcs12(
      Uint8List.fromList(store.readAsBytesSync()),
      storePassword: kDebugKeyPassword,
      alias: kDebugKeyAlias,
    );
  } on FormatException {
    return null;
  }
}

/// `key.properties` as Flutter's Android template reads it (Java
/// properties: `key=value`, `#` and `!` comments).
Map<String, String> parseKeyProperties(String text) => {
  for (final line in text.split(RegExp(r'\r?\n')).map((l) => l.trim()))
    if (line.isNotEmpty &&
        !line.startsWith('#') &&
        !line.startsWith('!') &&
        line.contains(RegExp('[=:]')))
      line.substring(0, line.indexOf(RegExp('[=:]'))).trim(): line
          .substring(line.indexOf(RegExp('[=:]')) + 1)
          .trim(),
};
