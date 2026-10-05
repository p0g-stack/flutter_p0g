import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/web_template.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../p0g_cache.dart';
import 'dart_android.dart';

/// flutter-webui, pinned: its bootstrap (`bootstrap/`) replaces the app's
/// `web/index.html` and `flutter_bootstrap.js` in WebUI builds, and its
/// `web_ui/` patch series builds the patched web SDK the build compiles
/// against.
const kFlutterWebuiRepo = 'https://github.com/p0g-stack/flutter-webui';
const kFlutterWebuiCommit = '60c0b775773ae2abfce8ed5b333aab5643483972';

/// flutter-webui's released patched web SDK (`web-sdk-release` workflow):
/// `flutter_web_sdk/` and `pkg/sky_engine/lib/ui_web/`, built from the
/// `web_ui/` tree [kWebSdkTree] against engine [kWebSdkEngine], pinned by
/// sha256. Used when the pinned flutter-webui has that `web_ui/` tree and
/// the installed Flutter that engine; otherwise precache builds it.
const kWebSdkRelease = 'web-sdk-3.47.5-af7e796-93b29c6';
const kWebSdkTree = '2b9eb411934f0eed8ecf8b7b59fcbfce70686bd0';
const kWebSdkEngine = 'af7e796e161ae0bb1ff0758c71a7105418bd9ded';
const kWebSdkSha256 = 'c961ec08b216b5f7a554a6e426003246d17edfd5db922689d710d990363d7ae7';
const kWebSdkUrl =
    '$kFlutterWebuiRepo/releases/download/$kWebSdkRelease/flutter-webui-web-sdk.tar.xz';

/// Whether the released SDK fits: same `web_ui/` tree, same engine.
@visibleForTesting
bool releasedWebSdkFits({required String tree, required String engine}) =>
    tree == kWebSdkTree && engine == kWebSdkEngine;

Directory flutterWebuiDir() => p0gCacheDir().childDirectory('flutter-webui');
Directory flutterWebuiSource() => flutterWebuiDir().childDirectory('src');
Directory bootstrapDir() => flutterWebuiSource().childDirectory('bootstrap');

/// web_ui's fallback fonts (`web_ui/tool/fallback_fonts.dart`, default set):
/// the module's `webroot/fonts/` and the dev server's `fonts/`.
Directory fallbackFontsDir() => flutterWebuiDir().childDirectory('fonts');

/// The root channel's package (`packages/flutter_webui_root`).
Directory rootChannelPackage() =>
    flutterWebuiSource().childDirectory('packages').childDirectory('flutter_webui_root');

/// Root of the patched SDK (`flutter_web_sdk/` inside), mirroring bin/cache.
Directory patchedWebSdkRoot() => flutterWebuiDir().childDirectory('sdk');
Directory patchedWebSdk() => patchedWebSdkRoot().childDirectory('flutter_web_sdk');

/// Files the release page uses; `dev.html` is only for `run`.
const kBootstrapFiles = [
  'index.html',
  'flutter_bootstrap.js',
  'flutter_webui.js',
  'flutter_webui.css',
];

/// Fetches flutter-webui at the pin and builds the patched web SDK with its
/// own tool. The source is stamped by commit; the SDK and fonts by the
/// `web_ui/` tree they come from, so a pin bump that leaves `web_ui/` alone
/// (plugin or bootstrap only) does not rebuild them. [force] redoes both.
Future<void> precacheFlutterWebui({bool force = false}) async {
  final stamp = flutterWebuiDir().childFile('stamp');
  final sdkStamp = flutterWebuiDir().childFile('sdk-stamp');
  final src = flutterWebuiSource();
  Future<void> run(List<String> cmd, String cwd) async {
    final code = await globals.processUtils.stream(cmd, workingDirectory: cwd);
    if (code != 0) throwToolExit('${cmd.take(3).join(' ')} failed (exit $code).');
  }

  final sourceCurrent =
      !force && stamp.existsSync() && stamp.readAsStringSync() == kFlutterWebuiCommit;
  if (!sourceCurrent) {
    if (src.existsSync()) src.deleteSync(recursive: true);
    src.createSync(recursive: true);
    globals.printStatus('Fetching flutter-webui ${kFlutterWebuiCommit.substring(0, 7)}...');
    await run(['git', 'init', '-q'], src.path);
    await run(['git', 'remote', 'add', 'origin', kFlutterWebuiRepo], src.path);
    await run(['git', 'fetch', '-q', '--depth', '1', 'origin', kFlutterWebuiCommit], src.path);
    await run(['git', 'checkout', '-q', 'FETCH_HEAD'], src.path);
    // The root channel and the plugin resolve against the source's workspace.
    await run([dartBinary(), 'pub', 'get'], src.path);
    stamp.writeAsStringSync(kFlutterWebuiCommit);
  }

  final tree = await webUiTree(src);
  if (!force &&
      sdkStamp.existsSync() &&
      sdkStamp.readAsStringSync() == tree &&
      patchedWebSdk().childDirectory('kernel').existsSync() &&
      fallbackFontsDir().existsSync()) {
    return;
  }
  final webUi = src.childDirectory('web_ui').path;
  await run([dartBinary(), 'pub', 'get'], webUi);
  final engine = globals.flutterVersion.engineRevision;
  if (!releasedWebSdkFits(tree: tree, engine: engine) || !await _installReleasedWebSdk()) {
    globals.printStatus('Building the patched web SDK (flutter-webui web_ui/tool)...');
    await run([
      dartBinary(), 'run', 'tool/build_web_sdk.dart', //
      '--flutter', Cache.flutterRoot!, '--out', patchedWebSdkRoot().path,
    ], webUi);
  }

  globals.printStatus("Fetching web_ui's fallback fonts...");
  final fonts = fallbackFontsDir();
  if (fonts.existsSync()) fonts.deleteSync(recursive: true);
  await run([
    dartBinary(), 'run', 'tool/fallback_fonts.dart', //
    '--flutter', Cache.flutterRoot!, '--out', fonts.path,
    '--cache', flutterWebuiDir().childDirectory('fonts-cache').path,
  ], webUi);
  sdkStamp.writeAsStringSync(tree);
}

/// Downloads [kWebSdkUrl], checks [kWebSdkSha256] and unpacks it as
/// [patchedWebSdkRoot]. False (after a warning) when any step fails, so the
/// caller builds the SDK instead.
Future<bool> _installReleasedWebSdk() async {
  globals.printStatus('Fetching the patched web SDK ($kWebSdkRelease)...');
  final work = flutterWebuiDir().childDirectory('sdk-download');
  try {
    final bytes = await fetchBytes(kWebSdkUrl);
    final digest = sha256.convert(bytes).toString();
    if (digest != kWebSdkSha256) {
      globals.printWarning('$kWebSdkRelease: sha256 is $digest, the pin says $kWebSdkSha256.');
      return false;
    }
    if (work.existsSync()) work.deleteSync(recursive: true);
    final unpacked = work.childDirectory('sdk')..createSync(recursive: true);
    final archive = work.childFile('web-sdk.tar.xz')..writeAsBytesSync(bytes);
    final r = await globals.processUtils.run([
      'tar', '-xJf', archive.path, '-C', unpacked.path, //
    ]);
    if (r.exitCode != 0 ||
        !unpacked.childDirectory('flutter_web_sdk').childDirectory('kernel').existsSync()) {
      globals.printWarning('$kWebSdkRelease: could not unpack it (tar with xz):\n${r.stderr}');
      return false;
    }
    final root = patchedWebSdkRoot();
    if (root.existsSync()) root.deleteSync(recursive: true);
    unpacked.renameSync(root.path);
    return true;
  } on ToolExit catch (e) {
    globals.printWarning('$kWebSdkRelease: ${e.message}');
    return false;
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}

/// The git tree id of [src]'s `web_ui/`: the patch series, its tool and the
/// fallback font list.
@visibleForTesting
Future<String> webUiTree(Directory src) async {
  final r = await globals.processUtils.run([
    'git',
    'rev-parse',
    'HEAD:web_ui',
  ], workingDirectory: src.path);
  if (r.exitCode != 0) throwToolExit('git rev-parse HEAD:web_ui failed:\n${r.stderr}');
  return r.stdout.trim();
}

/// flutter-webui's root channel for the module (`docs/root-channel.md`):
/// `flutter_webui/root` and, per kit, `flutter_webui/<abi>/` with the
/// channel's snapshot and the runtime.
Future<Map<String, List<int>>> rootChannelFiles(
  Map<String, DartAndroidKit> kits,
  Directory work,
) async {
  final pkg = rootChannelPackage();
  final aots = await compileAndroidAot(
    entrypoint: pkg.childDirectory('bin').childFile('flutter_webui_root.dart'),
    packageConfig: flutterWebuiSource()
        .childDirectory('.dart_tool')
        .childFile('package_config.json'),
    name: 'flutter_webui_root',
    kits: kits,
    work: work,
  );
  return {
    'flutter_webui/root': pkg.childDirectory('module').childFile('root').readAsBytesSync(),
    for (final MapEntry(key: abi, value: aot) in aots.entries) ...{
      'flutter_webui/$abi/flutter_webui_root.aot': aot.readAsBytesSync(),
      'flutter_webui/$abi/dartaotruntime': kits[abi]!.runtime.readAsBytesSync(),
    },
  };
}

/// Pulls the `_flutter.buildConfig = {...};` block flutter_tools wrote into
/// the stock `flutter_bootstrap.js`, so the bootstrap's own template can be
/// filled with the same config.
String? extractBuildConfig(String builtBootstrap) {
  final m = RegExp(
    r'if \(!window\._flutter\) \{\n  window\._flutter = \{\};\n\}\n'
    r'_flutter\.buildConfig = .*;\n',
  ).firstMatch(builtBootstrap);
  return m?.group(0);
}

/// Fills the bootstrap `index.html`'s module id and title.
@visibleForTesting
String fillIndexHtml(String html, {required String moduleId, required String title}) => html
    .replaceFirst(
      '<meta name="webui-module-id" content="">',
      '<meta name="webui-module-id" content="${htmlAttr(moduleId)}">',
    )
    .replaceFirst(RegExp('<title>[^<]*</title>'), '<title>${_text(title)}</title>');

String htmlAttr(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
String _text(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

/// Replaces the stock page in [web] (a `flutter build web` output) with the
/// flutter-webui bootstrap.
void applyBootstrap(Directory web, {required String moduleId, required String title}) {
  final boot = bootstrapDir();
  final built = web.childFile('flutter_bootstrap.js');
  final config = extractBuildConfig(built.readAsStringSync());
  if (config == null) throwToolExit('Could not find the build config in ${built.path}.');
  final flutterJs = flutterJsFile();
  built.writeAsStringSync(
    fillBootstrap(
      boot.childFile('flutter_bootstrap.js').readAsStringSync(),
      flutterJs: flutterJs,
      buildConfig: config,
    ),
  );
  web
      .childFile('index.html')
      .writeAsStringSync(
        fillIndexHtml(
          boot.childFile('index.html').readAsStringSync(),
          moduleId: moduleId,
          title: title,
        ),
      );
  for (final name in ['flutter_webui.js', 'flutter_webui.css']) {
    boot.childFile(name).copySync(web.childFile(name).path);
  }
}

/// flutter-webui's `flutter_bootstrap.js` template, filled as flutter_tools
/// fills `web/flutter_bootstrap.js`.
String fillBootstrap(String template, {required File flutterJs, required String buildConfig}) =>
    WebTemplate(template).withSubstitutions(
      baseHref: '',
      serviceWorkerVersion: null,
      flutterJsFile: flutterJs,
      buildConfig: buildConfig,
      logger: globals.logger,
    );

/// flutter.js from the web SDK in use.
File flutterJsFile() => globals.fs.file(
  globals.fs.path.join(
    globals.artifacts!.getHostArtifact(HostArtifact.flutterJsDirectory).path,
    'flutter.js',
  ),
);

/// [path] under [patched] when it is [stock] or inside it, else unchanged.
@visibleForTesting
String rebaseWebSdkPath(p.Context ctx, String path, String stock, String patched) =>
    path == stock || ctx.isWithin(stock, path)
    ? ctx.join(patched, ctx.relative(path, from: stock))
    : path;

/// Artifacts that point flutter_tools at the patched web SDK when it is built,
/// leaving the shared Flutter cache untouched.
class P0gArtifacts implements Artifacts {
  P0gArtifacts(this._inner, {required this.stockWebSdk, required this.patchedWebSdk});

  final Artifacts _inner;
  final String stockWebSdk;
  final Directory patchedWebSdk;

  /// Set by `build web`: the plain web target keeps the stock web SDK for
  /// the whole run, patched SDK built or not.
  static bool useStockWebSdk = false;

  String _rebase(String path) {
    if (useStockWebSdk || !patchedWebSdk.childDirectory('kernel').existsSync()) return path;
    return rebaseWebSdkPath(globals.fs.path, path, stockWebSdk, patchedWebSdk.path);
  }

  @override
  String getArtifactPath(
    Artifact artifact, {
    TargetPlatform? platform,
    BuildMode? mode,
    EnvironmentType? environmentType,
  }) => _rebase(
    _inner.getArtifactPath(
      artifact,
      platform: platform,
      mode: mode,
      environmentType: environmentType,
    ),
  );

  @override
  FileSystemEntity getHostArtifact(HostArtifact artifact) {
    final FileSystemEntity e = _inner.getHostArtifact(artifact);
    final path = _rebase(e.path);
    if (path == e.path) return e;
    return e is Directory ? globals.fs.directory(path) : globals.fs.file(path);
  }

  @override
  String getEngineType(TargetPlatform platform, [BuildMode? mode]) =>
      _inner.getEngineType(platform, mode);

  @override
  bool get usesLocalArtifacts => _inner.usesLocalArtifacts;

  @override
  LocalEngineInfo? get localEngineInfo => _inner.localEngineInfo;
}
