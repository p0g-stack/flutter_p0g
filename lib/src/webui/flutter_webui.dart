import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/web_template.dart';
import 'package:meta/meta.dart';

import '../p0g_cache.dart';

/// flutter-webui, pinned: its bootstrap (`bootstrap/`) replaces the app's
/// `web/index.html` and `flutter_bootstrap.js` in WebUI builds, and its
/// `web_ui/` patch series builds the patched web SDK the build compiles
/// against.
const kFlutterWebuiRepo = 'https://github.com/p0g-stack/flutter-webui';
const kFlutterWebuiCommit = '3049dc94adb1df919ccdab1ab305759601a772c3';

Directory flutterWebuiDir() => p0gCacheDir().childDirectory('flutter-webui');
Directory flutterWebuiSource() => flutterWebuiDir().childDirectory('src');
Directory bootstrapDir() => flutterWebuiSource().childDirectory('bootstrap');

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
/// own tool. Stamped by commit; [force] rebuilds.
Future<void> precacheFlutterWebui({bool force = false}) async {
  final stamp = flutterWebuiDir().childFile('stamp');
  if (!force &&
      stamp.existsSync() &&
      stamp.readAsStringSync() == kFlutterWebuiCommit &&
      patchedWebSdk().childDirectory('kernel').existsSync()) {
    return;
  }
  final src = flutterWebuiSource();
  if (src.existsSync()) src.deleteSync(recursive: true);
  src.createSync(recursive: true);
  Future<void> run(List<String> cmd, String cwd) async {
    final code = await globals.processUtils.stream(cmd, workingDirectory: cwd);
    if (code != 0) throwToolExit('${cmd.take(3).join(' ')} failed (exit $code).');
  }

  globals.printStatus('Fetching flutter-webui ${kFlutterWebuiCommit.substring(0, 7)}...');
  await run(['git', 'init', '-q'], src.path);
  await run(['git', 'remote', 'add', 'origin', kFlutterWebuiRepo], src.path);
  await run(['git', 'fetch', '-q', '--depth', '1', 'origin', kFlutterWebuiCommit], src.path);
  await run(['git', 'checkout', '-q', 'FETCH_HEAD'], src.path);

  globals.printStatus('Building the patched web SDK (flutter-webui web_ui/tool)...');
  final webUi = src.childDirectory('web_ui').path;
  await run([dartBinary(), 'pub', 'get'], webUi);
  await run([
    dartBinary(), 'run', 'tool/build_web_sdk.dart', //
    '--flutter', Cache.flutterRoot!, '--out', patchedWebSdkRoot().path,
  ], webUi);
  stamp.writeAsStringSync(kFlutterWebuiCommit);
}

/// Pulls the `_flutter.buildConfig = {...};` block flutter_tools wrote into
/// the stock `flutter_bootstrap.js`, so the bootstrap's own template can be
/// filled with the same config.
@visibleForTesting
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
      '<meta name="webui-module-id" content="${_attr(moduleId)}">',
    )
    .replaceFirst(RegExp('<title>[^<]*</title>'), '<title>${_text(title)}</title>');

String _attr(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
String _text(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

/// Replaces the stock page in [web] (a `flutter build web` output) with the
/// flutter-webui bootstrap.
void applyBootstrap(Directory web, {required String moduleId, required String title}) {
  final boot = bootstrapDir();
  final built = web.childFile('flutter_bootstrap.js');
  final config = extractBuildConfig(built.readAsStringSync());
  if (config == null) throwToolExit('Could not find the build config in ${built.path}.');
  final flutterJs = globals.fs.file(
    globals.fs.path.join(
      globals.artifacts!.getHostArtifact(HostArtifact.flutterJsDirectory).path,
      'flutter.js',
    ),
  );
  built.writeAsStringSync(
    WebTemplate(boot.childFile('flutter_bootstrap.js').readAsStringSync()).withSubstitutions(
      baseHref: '',
      serviceWorkerVersion: null,
      flutterJsFile: flutterJs,
      buildConfig: config,
      logger: globals.logger,
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

/// Artifacts that point flutter_tools at the patched web SDK when it is built,
/// leaving the shared Flutter cache untouched.
class P0gArtifacts implements Artifacts {
  P0gArtifacts(this._inner, {required this.stockWebSdk, required this.patchedWebSdk});

  final Artifacts _inner;
  final String stockWebSdk;
  final Directory patchedWebSdk;

  String _rebase(String path) {
    if (!patchedWebSdk.childDirectory('kernel').existsSync()) return path;
    final fs = globals.fs.path;
    if (path == stockWebSdk || fs.isWithin(stockWebSdk, path)) {
      return fs.join(patchedWebSdk.path, fs.relative(path, from: stockWebSdk));
    }
    return path;
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
