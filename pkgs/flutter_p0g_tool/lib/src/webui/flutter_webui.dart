import 'dart:convert';

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

import '../artifact_lock.dart';
import '../p0g_cache.dart';
import '../p0g_repository.dart';
import 'dart_android.dart';
import 'webui_packages.dart';

/// Whether the locked web SDK release (`artifacts.lock.json` `webSdk`:
/// `flutter_web_sdk/` and `pkg/sky_engine/lib/ui_web/`) fits: built from the
/// same patch set ([webSdkPatchSet]) against this engine. How `web_sdk/` is
/// packaged (its pubspec, its tool) does not change what the SDK holds.
@visibleForTesting
Future<bool> releasedWebSdkFits({required String patchSet, required String engine}) async {
  final lock = await artifactLock();
  return patchSet == lock.webSdk.field('patchSet') && engine == lock.engine;
}

/// The digest of what [patches] (`web_sdk/patches`) change: for each
/// `*.patch` in name order, its diff from the first `diff --git` line up to
/// the signature, without `index` lines. Commit metadata and blob ids, which
/// a rebase or re-export rewrites, stay out; any change to a hunk changes it.
@visibleForTesting
String webSdkPatchSet(Directory patches) {
  final files =
      patches.listSync().whereType<File>().where((f) => f.basename.endsWith('.patch')).toList()
        ..sort((a, b) => a.basename.compareTo(b.basename));
  if (files.isEmpty) throwToolExit('${patches.path} holds no patches.');
  final bytes = <int>[];
  for (final file in files) {
    final lines = const LineSplitter().convert(file.readAsStringSync());
    final start = lines.indexWhere((l) => l.startsWith('diff --git '));
    if (start < 0) throwToolExit('${file.path} holds no diff.');
    final body = <String>[];
    for (final line in lines.skip(start)) {
      if (line == '-- ') break;
      if (!line.startsWith('index ')) body.add(line);
    }
    bytes.addAll(utf8.encode('${body.join('\n')}\n'));
  }
  return sha256.convert(bytes).toString();
}

/// Puts the patched web SDK in [patchedWebSdkRoot]: the locked release when
/// it fits ([releasedWebSdkFits]), else [buildLocally]. The `sdk-stamp`
/// names the source (the release's url and sha256, or the local patch set)
/// and the engine, so only a lock, patch or engine change replaces the SDK.
/// [force] redoes it.
Future<void> ensurePatchedWebSdk({
  required Directory repo,
  required bool force,
  required Future<void> Function() buildLocally,
}) async {
  final engine = globals.flutterVersion.engineRevision;
  final patchSet = webSdkPatchSet(repoDirectory(repo, kWebSdkPath).childDirectory('patches'));
  final fits = await releasedWebSdkFits(patchSet: patchSet, engine: engine);
  final asset = (await artifactLock()).webSdk.single;
  final stamp = jsonEncode(
    fits
        ? {'url': asset.url, 'sha256': asset.sha256, 'engine': engine}
        : {'patchSet': patchSet, 'engine': engine},
  );
  final stampFile = flutterWebuiDir().childFile('sdk-stamp');
  if (!force &&
      stampFile.existsSync() &&
      stampFile.readAsStringSync() == stamp &&
      patchedWebSdk().childDirectory('kernel').existsSync()) {
    return;
  }
  if (stampFile.existsSync()) stampFile.deleteSync();
  if (fits) {
    await installReleasedWebSdk();
  } else {
    await buildLocally();
  }
  stampFile
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(stamp);
}

/// What precache builds for WebUI: the patched web SDK and the fallback fonts.
Directory flutterWebuiDir() => p0gCacheDir().childDirectory('flutter-webui');

/// flutter_webui's bootstrap (`bootstrap/`, read from the repository): it
/// replaces the app's `web/index.html` and `flutter_bootstrap.js` in WebUI
/// builds.
Future<Directory> bootstrapDir() async =>
    repoDirectory(await p0gRepository(), kFlutterWebuiPath).childDirectory('bootstrap');

/// web_ui's fallback fonts (`web_sdk/tool/fallback_fonts.dart`, default set):
/// the module's `webroot/fonts/` and the dev server's `fonts/`.
Directory fallbackFontsDir() => flutterWebuiDir().childDirectory('fonts');

/// The root channel's package (`pkgs/flutter_webui_root`).
Future<Directory> rootChannelPackage() async =>
    repoDirectory(await p0gRepository(), 'pkgs/flutter_webui_root');

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

/// Resolves the repository's WebUI packages ([precacheWebuiSources]), puts
/// the patched web SDK in place ([ensurePatchedWebSdk], built locally with
/// the repository's `web_sdk/tool` when no locked release fits) and fetches
/// web_ui's fallback fonts. The fonts are stamped by the font tool's bytes
/// and the engine whose font list it reads. [force] redoes all three. The
/// tools run against the resolved package config, so nothing is written
/// into the repository.
Future<void> precacheFlutterWebui({bool force = false}) async {
  await precacheWebuiSources(force: force);
  final repo = await p0gRepository();
  final tool = repoDirectory(repo, kWebSdkPath).childDirectory('tool');
  Future<void> runTool(String script, List<String> args) async {
    final cmd = [
      dartBinary(),
      '--packages=${webuiSourcesPackageConfig().path}',
      tool.childFile(script).path,
      ...args,
    ];
    final code = await globals.processUtils.stream(cmd, workingDirectory: webuiSourcesDir().path);
    if (code != 0) throwToolExit('web_sdk/tool/$script failed (exit $code).');
  }

  await ensurePatchedWebSdk(
    repo: repo,
    force: force,
    buildLocally: () {
      globals.printStatus('Building the patched web SDK (web_sdk/tool)...');
      return runTool('build_web_sdk.dart', [
        '--flutter', Cache.flutterRoot!, '--out', patchedWebSdkRoot().path, //
      ]);
    },
  );

  final fontsTool = tool.childFile('fallback_fonts.dart');
  final fontsStamp = flutterWebuiDir().childFile('fonts-stamp');
  final fontsKey = sha256.convert([
    ...fontsTool.readAsBytesSync(),
    ...utf8.encode(globals.flutterVersion.engineRevision),
  ]).toString();
  final fonts = fallbackFontsDir();
  if (!force &&
      fontsStamp.existsSync() &&
      fontsStamp.readAsStringSync() == fontsKey &&
      fonts.existsSync()) {
    return;
  }
  globals.printStatus("Fetching web_ui's fallback fonts...");
  if (fonts.existsSync()) fonts.deleteSync(recursive: true);
  await runTool('fallback_fonts.dart', [
    '--flutter', Cache.flutterRoot!, '--out', fonts.path, //
    '--cache', flutterWebuiDir().childDirectory('fonts-cache').path,
  ]);
  fontsStamp.writeAsStringSync(fontsKey);
}

/// Installs the locked web SDK, propagating download and integrity failures.
@visibleForTesting
Future<void> installReleasedWebSdk({Future<List<int>> Function(String) fetch = fetchBytes}) async {
  final release = (await artifactLock()).webSdk;
  final asset = release.single;
  globals.printStatus('Fetching the patched web SDK (${release.tag})...');
  final work = flutterWebuiDir().childDirectory('sdk-download');
  try {
    final bytes = await fetch(asset.url);
    final digest = sha256.convert(bytes).toString();
    if (digest != asset.sha256) {
      throwToolExit('${release.tag}: sha256 is $digest, the lock says ${asset.sha256}.');
    }
    if (work.existsSync()) work.deleteSync(recursive: true);
    final unpacked = work.childDirectory('sdk')..createSync(recursive: true);
    final archive = work.childFile('web-sdk.tar.xz')..writeAsBytesSync(bytes);
    final r = await globals.processUtils.run([
      'tar', '-xJf', archive.path, '-C', unpacked.path, //
    ]);
    if (r.exitCode != 0 ||
        !unpacked.childDirectory('flutter_web_sdk').childDirectory('kernel').existsSync()) {
      throwToolExit('${release.tag}: could not unpack it (tar with xz):\n${r.stderr}');
    }
    final root = patchedWebSdkRoot();
    if (root.existsSync()) root.deleteSync(recursive: true);
    unpacked.renameSync(root.path);
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}

/// flutter_webui_root, the root channel, for the module (flutter_webui
/// `docs/root-channel.md`): `flutter_webui/root` and, per kit,
/// `flutter_webui/<abi>/` with the channel's snapshot and the runtime.
Future<Map<String, List<int>>> rootChannelFiles(
  Map<String, DartAndroidKit> kits,
  Directory work,
) async {
  final pkg = await rootChannelPackage();
  final aots = await compileAndroidAot(
    entrypoint: pkg.childDirectory('bin').childFile('flutter_webui_root.dart'),
    packageConfig: webuiSourcesPackageConfig(),
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
/// flutter_webui bootstrap.
Future<void> applyBootstrap(
  Directory web, {
  required String moduleId,
  required String title,
}) async {
  final boot = await bootstrapDir();
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

/// flutter_webui's `flutter_bootstrap.js` template, filled as flutter_tools
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
