import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:yaml/yaml.dart';

import '../p0g_cache.dart';

/// webui-packages, pinned: the `*_webui` implementations of stock plugins
/// and `webui_app_plane` (the Termux:API client the app plane runs).
const kWebuiPackagesRepo = 'https://github.com/p0g-stack/webui-packages';
const kWebuiPackagesCommit = '9b77c337e3b90e4801b46e34d386c86dd97743a8';

Directory webuiPackagesDir() => p0gCacheDir().childDirectory('webui-packages');
Directory webuiPackagesSource() => webuiPackagesDir().childDirectory('src');

/// Fetches webui-packages at the pin and resolves its workspace. Stamped by
/// commit; [force] fetches again.
Future<void> precacheWebuiPackages({bool force = false}) async {
  final stamp = webuiPackagesDir().childFile('stamp');
  final src = webuiPackagesSource();
  if (!force &&
      stamp.existsSync() &&
      stamp.readAsStringSync() == kWebuiPackagesCommit &&
      src.childDirectory('.dart_tool').childFile('package_graph.json').existsSync()) {
    return;
  }
  if (src.existsSync()) src.deleteSync(recursive: true);
  src.createSync(recursive: true);
  Future<void> run(List<String> cmd) async {
    final code = await globals.processUtils.stream(cmd, workingDirectory: src.path);
    if (code != 0) throwToolExit('${cmd.take(3).join(' ')} failed (exit $code).');
  }

  globals.printStatus('Fetching webui-packages ${kWebuiPackagesCommit.substring(0, 7)}...');
  await run(['git', 'init', '-q']);
  await run(['git', 'remote', 'add', 'origin', kWebuiPackagesRepo]);
  await run(['git', 'fetch', '-q', '--depth', '1', 'origin', kWebuiPackagesCommit]);
  await run(['git', 'checkout', '-q', 'FETCH_HEAD']);
  await run([globals.fs.path.join(Cache.flutterRoot!, 'bin', 'flutter'), 'pub', 'get']);
  stamp.writeAsStringSync(kWebuiPackagesCommit);
}

/// The `*_webui` packages in webui-packages by the plugin each implements
/// (`flutter: plugin: implements:`).
Map<String, String> webuiImplementations() {
  final out = <String, String>{};
  final packages = webuiPackagesSource().childDirectory('packages');
  if (!packages.existsSync()) return out;
  for (final dir in packages.listSync().whereType<Directory>()) {
    final pubspec = dir.childFile('pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final doc = loadYaml(pubspec.readAsStringSync());
    if (doc is! YamlMap) continue;
    final flutter = doc['flutter'];
    final plugin = flutter is YamlMap ? flutter['plugin'] : null;
    final implements = plugin is YamlMap ? plugin['implements'] : null;
    if (implements is String) out[implements] = doc['name'] as String;
  }
  return out;
}
