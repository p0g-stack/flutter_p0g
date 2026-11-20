import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import '../p0g_cache.dart';
import '../p0g_repository.dart';

/// The repository's packages a WebUI build uses, by path from its root:
/// the flutter_webui plugin and its client and root channel, the web SDK
/// build tool and, in [kWebuiPackagesPath], the `*_webui` implementations of
/// stock plugins and `webui_app_plane` (the Termux:API client the app plane
/// runs).
const kFlutterWebuiPath = 'pkgs/flutter_webui';
const kWebSdkPath = 'web_sdk';
const kWebuiPackagesPath = 'pkgs/webui';
const _kWebuiSourcePaths = [
  kFlutterWebuiPath,
  'pkgs/flutter_webui_client',
  'pkgs/flutter_webui_root',
  kWebSdkPath,
];

Directory repoDirectory(Directory repo, String path) =>
    repo.childDirectory(globals.fs.path.joinAll(path.split('/')));

/// The `*_webui` packages of [repo].
Directory webuiPackagesDir(Directory repo) => repoDirectory(repo, kWebuiPackagesPath);

/// Where the repository's WebUI packages are resolved: a package of their
/// own that depends on each by path, so `pub get` writes only here and never
/// into the repository (which may be a pub git cache).
Directory webuiSourcesDir() => p0gCacheDir().childDirectory('webui-sources');

/// The resolved package config of [webuiSourcesDir].
File webuiSourcesPackageConfig() =>
    webuiSourcesDir().childDirectory('.dart_tool').childFile('package_config.json');

/// The packages [precacheWebuiSources] resolves, by name, as paths from the
/// repository root.
Map<String, String> webuiSourcePackages(Directory repo) {
  final paths = [
    ..._kWebuiSourcePaths,
    for (final dir in webuiPackagesDir(
      repo,
    ).listSync().whereType<Directory>().toList()..sort(_byPath))
      if (dir.childFile('pubspec.yaml').existsSync()) '$kWebuiPackagesPath/${dir.basename}',
  ];
  return {for (final path in paths) _packageName(repoDirectory(repo, path)): path};
}

int _byPath(Directory a, Directory b) => a.path.compareTo(b.path);

String _packageName(Directory dir) {
  final file = dir.childFile('pubspec.yaml');
  if (!file.existsSync()) throwToolExit('${dir.path} has no pubspec.yaml.');
  final doc = loadYaml(file.readAsStringSync());
  final name = doc is YamlMap ? doc['name'] : null;
  if (name is! String) throwToolExit('${file.path} has no name.');
  return name;
}

/// The pubspec of the package that resolves [packages] (name to path from
/// [repo]) with the repository's SDK constraint.
@visibleForTesting
String webuiSourcesPubspec(Directory repo, Map<String, String> packages) {
  final doc = loadYaml(repo.childFile('pubspec.yaml').readAsStringSync());
  final env = doc is YamlMap ? doc['environment'] : null;
  final sdk = env is YamlMap ? env['sdk'] : null;
  if (sdk is! String) throwToolExit('${repo.path}/pubspec.yaml has no environment sdk.');
  return [
    'name: flutter_p0g_webui_sources',
    'publish_to: none',
    'environment:',
    '  sdk: ${jsonEncode(sdk)}',
    'dependencies:',
    for (final MapEntry(key: name, value: path) in packages.entries)
      '  $name:\n    path: ${jsonEncode(repoDirectory(repo, path).path)}',
    '',
  ].join('\n');
}

/// Resolves the repository's WebUI packages in [webuiSourcesDir], from the
/// repository's own `pubspec.lock` so they get the versions its CI tested.
/// Stamped by the generated pubspec and the bytes of every pubspec and lock
/// it comes from; [force] resolves again.
Future<void> precacheWebuiSources({bool force = false}) async {
  final repo = await p0gRepository();
  final packages = webuiSourcePackages(repo);
  final pubspec = webuiSourcesPubspec(repo, packages);
  final lock = repo.childFile('pubspec.lock');
  final stamp = sha256.convert([
    ...utf8.encode(pubspec),
    if (lock.existsSync()) ...lock.readAsBytesSync(),
    for (final path in packages.values)
      ...repoDirectory(repo, path).childFile('pubspec.yaml').readAsBytesSync(),
  ]).toString();
  final dir = webuiSourcesDir();
  final stampFile = dir.childFile('stamp');
  if (!force &&
      stampFile.existsSync() &&
      stampFile.readAsStringSync() == stamp &&
      dir.childDirectory('.dart_tool').childFile('package_graph.json').existsSync()) {
    return;
  }
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  dir.childFile('pubspec.yaml').writeAsStringSync(pubspec);
  if (lock.existsSync()) lock.copySync(dir.childFile('pubspec.lock').path);
  globals.printStatus('Resolving the WebUI packages of ${repo.path}...');
  final code = await globals.processUtils.stream([
    globals.fs.path.join(Cache.flutterRoot!, 'bin', 'flutter'),
    'pub',
    'get',
  ], workingDirectory: dir.path);
  if (code != 0) throwToolExit('flutter pub get failed (exit $code) in ${dir.path}.');
  stampFile.writeAsStringSync(stamp);
}

/// The `*_webui` packages in [packages] by the plugin each implements
/// (`flutter: plugin: implements:`).
Map<String, String> webuiImplementations(Directory packages) {
  final out = <String, String>{};
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
