import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import '../p0g_cache.dart';
import 'dart_android.dart';
import 'webui_packages.dart';

/// The app plane's lock: the webui-termux-api release every module ships,
/// pinned by tag and sha256. Modules mount it at the same path, so they must
/// all carry the same APK (proposals/app-plane-termux-api.md, "Overlay
/// collisions"); bump it here only.
const kAppPlaneRepo = 'https://github.com/p0g-stack/webui-termux-api';
const kAppPlaneTag = 'webui-v0.53.0-webui.2';
const kAppPlaneAsset = 'webui-termux-api_v0.53.0-webui.2.apk';
const kAppPlaneSha256 = 'b6925a96aa7e8fdd919c22aa10a177bd72acac9524bfcc80e2708fc705b084e2';

/// Where the module carries the APK: a non-privileged product app.
const kAppPlaneApkPath = 'system/product/app/WebuiTermuxApi/WebuiTermuxApi.apk';

/// The package that brings the app plane in.
const kAppPlanePackage = 'webui_app_plane';

File appPlaneApk() => p0gCacheDir()
    .childDirectory('app-plane')
    .childDirectory(kAppPlaneTag)
    .childFile('WebuiTermuxApi.apk');

/// Fetches the pinned APK and checks its sha256. [source] replaces the
/// release URL (a path or URL; the pin still applies).
Future<void> precacheAppPlane({String? source, bool force = false}) async {
  final apk = appPlaneApk();
  if (!force && source == null && apk.existsSync()) return;
  source ??= '$kAppPlaneRepo/releases/download/$kAppPlaneTag/$kAppPlaneAsset';
  final bytes = await fetchBytes(source);
  final digest = sha256.convert(bytes).toString();
  if (digest != kAppPlaneSha256) {
    throwToolExit('webui-termux-api: sha256 is $digest, the lock says $kAppPlaneSha256.');
  }
  apk
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  globals.printStatus('webui-termux-api $kAppPlaneTag installed (sha256 $digest).');
}

/// The app plane's module files (webui-packages `docs/plugins.md`, "What
/// flutter_p0g ships"): the `termux-api` launcher, its snapshot per kit (run
/// by the root channel's runtime) and the APK.
Future<Map<String, List<int>>> appPlaneFiles(
  Map<String, DartAndroidKit> kits,
  Directory work,
) async {
  await precacheAppPlane();
  final pkg = webuiPackagesSource().childDirectory('packages').childDirectory(kAppPlanePackage);
  final aots = await compileAndroidAot(
    entrypoint: pkg.childDirectory('bin').childFile('webui_termux_api.dart'),
    packageConfig: webuiPackagesSource()
        .childDirectory('.dart_tool')
        .childFile('package_config.json'),
    name: 'webui_termux_api',
    kits: kits,
    work: work,
  );
  return {
    'webui_app_plane/termux-api': pkg
        .childDirectory('module')
        .childFile('termux-api')
        .readAsBytesSync(),
    for (final MapEntry(key: abi, value: aot) in aots.entries)
      'webui_app_plane/$abi/webui_termux_api.aot': aot.readAsBytesSync(),
    kAppPlaneApkPath: appPlaneApk().readAsBytesSync(),
  };
}
