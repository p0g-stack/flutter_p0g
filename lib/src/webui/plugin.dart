import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';

import 'package:flutter_tools/src/flutter_manifest.dart';

import '../project_factory.dart';
import 'flutter_webui.dart';
import 'webui_packages.dart';

/// The flutter-webui web plugin. It compiles only against the patched web
/// SDK, so apps depend on `flutter_webui_client` and WebUI builds add the
/// plugin: its packages join the package config for the build, and the
/// build target becomes an entrypoint that registers it before the app's
/// `main()`, the way flutter-tizen registers its embedding plugins from a
/// generated main.
const kWebuiPlugin = 'flutter_webui';

/// A resolved source of packages: its package_config.json, package_graph.json
/// and the directory holding them (relative root URIs resolve against it).
typedef PackageSource = ({Map<String, Object?> config, Map<String, Object?> graph, Uri dir});

/// [app] (a package_config.json) plus the closure of [seeds] it lacks, taken
/// from [sources] (the first source that has a package wins). Packages [app]
/// already has stay as they are. Relative root URIs are made absolute.
@visibleForTesting
({Map<String, Object?> config, List<String> added}) overlayPackageConfig(
  Map<String, Object?> app,
  List<PackageSource> sources,
  List<String> seeds,
) {
  final appPackages = [...(app['packages']! as List).cast<Map<String, Object?>>()];
  final have = {for (final p in appPackages) p['name']! as String};
  final srcPackages = <String, Map<String, Object?>>{};
  final deps = mergedDependencies(sources);
  for (final s in sources) {
    for (final p in (s.config['packages']! as List).cast<Map<String, Object?>>()) {
      srcPackages.putIfAbsent(
        p['name']! as String,
        () => {...p, 'rootUri': s.dir.resolve(p['rootUri']! as String).toString()},
      );
    }
  }

  final needed = <String>[];
  final queue = [...seeds];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (needed.contains(name)) continue;
    needed.add(name);
    queue.addAll(deps[name] ?? const []);
  }

  final added = <String>[];
  for (final name in needed) {
    if (have.contains(name)) continue;
    final p = srcPackages[name];
    if (p == null) throwToolExit('No resolution of package:$name for the WebUI build.');
    appPackages.add(p);
    added.add(name);
  }
  return (config: {...app, 'packages': appPackages}, added: added..sort());
}

/// Each package's dependencies across [sources] (first source wins).
Map<String, List<String>> mergedDependencies(List<PackageSource> sources) {
  final deps = <String, List<String>>{};
  for (final s in sources) {
    for (final p in (s.graph['packages']! as List).cast<Map<String, Object?>>()) {
      deps.putIfAbsent(
        p['name']! as String,
        () => (p['dependencies'] as List? ?? const []).cast<String>(),
      );
    }
  }
  return deps;
}

/// [graph] (the app's package_graph.json) with entries for [added] and
/// [direct] added to [root]'s dependencies, so flutter_tools finds them as
/// direct dependencies of the app.
@visibleForTesting
Map<String, Object?> overlayPackageGraph(
  Map<String, Object?> graph, {
  required String root,
  required List<String> added,
  required List<String> direct,
  required Map<String, List<String>> dependencies,
}) {
  final packages = [
    for (final p in (graph['packages']! as List).cast<Map<String, Object?>>())
      if (p['name'] == root)
        {
          ...p,
          'dependencies': {...(p['dependencies'] as List).cast<String>(), ...direct}.toList(),
        }
      else
        p,
  ];
  final have = {for (final p in packages) p['name']};
  for (final name in added) {
    if (have.contains(name)) continue;
    packages.add({'name': name, 'dependencies': dependencies[name] ?? const <String>[]});
  }
  return {...graph, 'packages': packages};
}

/// The packages [root] depends on, transitively, in [graph].
@visibleForTesting
Set<String> closureOf(Map<String, Object?> graph, String root) {
  final deps = mergedDependencies([(config: const {}, graph: graph, dir: Uri())]);
  final seen = <String>{};
  final queue = [...?deps[root]];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (seen.add(name)) queue.addAll(deps[name] ?? const []);
  }
  return seen;
}

/// `*_webui` packages every module gets, though no stock plugin package
/// names them: clipboard_webui backs Flutter's own `Clipboard` (a plain web
/// plugin, no `implements:`), so its `registerWith` must run.
const kAlwaysWebuiPackages = ['clipboard_webui'];

/// The `*_webui` packages the app needs as direct dependencies: those
/// implementing a plugin in [appClosure] that [appDirect] doesn't name.
/// Flutter registers one web implementation per plugin, and a `*_webui` one
/// wins over the stock `*_web` only as a direct dependency (webui-packages
/// `docs/plugins.md`). So does a `*_webui` package that another added one
/// depends on (by [addedDependencies], e.g. url_launcher_webui through
/// share_plus_webui), or else Flutter finds two web implementations of its
/// plugin; repeated until nothing new comes in. [always] are added to every
/// app ([kAlwaysWebuiPackages]).
@visibleForTesting
List<String> webuiPackagesFor(
  Set<String> appClosure,
  Set<String> appDirect,
  Map<String, String> implementations, {
  Map<String, List<String>> addedDependencies = const {},
  Set<String> always = const {},
}) {
  final closure = {...appClosure, ...always};
  final picked = <String>{};
  while (true) {
    final next = {
      for (final MapEntry(key: plugin, value: impl) in implementations.entries)
        if ((closure.contains(plugin) || closure.contains(impl)) && !appDirect.contains(impl)) impl,
      for (final impl in always)
        if (!appDirect.contains(impl)) impl,
    };
    if (next.length == picked.length) break;
    picked.addAll(next);
    final queue = [...picked];
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      for (final dep in addedDependencies[name] ?? const <String>[]) {
        if (closure.add(dep)) queue.add(dep);
      }
    }
  }
  return picked.toList()..sort();
}

/// A `main()` that registers [kWebuiPlugin] and runs the app's [appImport].
/// flutter_tools wraps it as it wraps any target, so the app's other web
/// plugins register first.
@visibleForTesting
String webuiEntrypoint(String appImport) =>
    '''
// Generated by flutter_p0g build webui. Do not edit.
// ignore_for_file: type=lint

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:$kWebuiPlugin/flutter_webui_web.dart';

import '$appImport' as app;

typedef _UnaryFunction = dynamic Function(List<String> args);
typedef _NullaryFunction = dynamic Function();

dynamic main() {
  FlutterWebUi.registerWith(webPluginRegistrar);
  final Function entry = app.main;
  if (entry is _UnaryFunction) return entry(<String>[]);
  return (entry as _NullaryFunction)();
}
''';

/// What the WebUI build adds to the app.
typedef WebuiOverlay = ({String entrypoint, Set<String> packages});

/// The package config and graph the build uses, overlaid with [kWebuiPlugin]
/// and the app's `*_webui` packages while [body] runs, then restored; the
/// project's manifest names the `*_webui` packages as dependencies
/// meanwhile. [body] gets the entrypoint to build in place of [target] and
/// every package the build resolves.
Future<T> withWebuiPlugin<T>(
  Directory project,
  String target,
  Future<T> Function(WebuiOverlay overlay) body,
) async {
  final appConfigFile = findPackageConfigFile(project);
  if (appConfigFile == null) throwToolExit('No package config. Run `flutter pub get`.');
  final appGraphFile = appConfigFile.parent.childFile('package_graph.json');
  PackageSource source(Directory src, String what) {
    final dart = src.childDirectory('.dart_tool');
    final config = dart.childFile('package_config.json');
    final graph = dart.childFile('package_graph.json');
    if (!config.existsSync() || !graph.existsSync()) {
      throwToolExit('$what is not resolved. Run `flutter_p0g precache --webui`.');
    }
    return (
      config: _json(config.readAsBytesSync()),
      graph: _json(graph.readAsBytesSync()),
      dir: dart.uri,
    );
  }

  final sources = [
    source(flutterWebuiSource(), 'flutter-webui'),
    source(webuiPackagesSource(), 'webui-packages'),
  ];

  // A run killed before it could restore leaves its backups: restore first.
  final backups = {
    for (final f in [appConfigFile, appGraphFile])
      f: f.parent.childFile('${f.basename}.flutter_p0g'),
  };
  backups.forEach((file, backup) {
    if (backup.existsSync()) {
      globals.printTrace('Restoring the ${file.basename} a previous build left overlaid.');
      backup.copySync(file.path);
    }
  });
  final originals = {for (final f in backups.keys) f: f.readAsBytesSync()};

  final flutterProject = globals.projectFactory.fromDirectory(project);
  final appName = flutterProject.manifest.appName;
  final appGraph = _json(originals[appGraphFile]!);
  final direct = webuiPackagesFor(
    closureOf(appGraph, appName),
    flutterProject.manifest.dependencies,
    webuiImplementations(),
    addedDependencies: mergedDependencies(sources),
    always: {
      for (final p in kAlwaysWebuiPackages)
        if (webuiPackagesSource().childDirectory('packages').childDirectory(p).existsSync()) p,
    },
  );
  final overlay = overlayPackageConfig(_json(originals[appConfigFile]!), sources, [
    kWebuiPlugin,
    ...direct,
  ]);
  final graph = overlayPackageGraph(
    appGraph,
    root: appName,
    added: overlay.added,
    direct: direct,
    dependencies: mergedDependencies(sources),
  );

  final appConfig = PackageConfig.parseBytes(originals[appConfigFile]!, appConfigFile.uri);
  final targetUri = globals.fs.file(target).absolute.uri;
  final appImport = (appConfig.toPackageUri(targetUri) ?? targetUri).toString();
  final entry =
      project
          .childDirectory('.dart_tool')
          .childDirectory('flutter_p0g')
          .childFile('webui_main.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(webuiEntrypoint(appImport));

  globals.printTrace('WebUI packages added: ${overlay.added.join(', ')}');
  if (direct.isNotEmpty) globals.printStatus('WebUI plugin implementations: ${direct.join(', ')}');
  originals.forEach((file, bytes) => backups[file]!.writeAsBytesSync(bytes));
  appConfigFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(overlay.config));
  appGraphFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(graph));
  // flutter_tools reads direct dependencies from the project's manifest.
  final factory = globals.projectFactory;
  final restoreManifest = direct.isNotEmpty && factory is P0gProjectFactory
      ? factory.overrideManifest(project, (m) => withDependencies(m, direct))
      : null;
  try {
    return await body((
      entrypoint: entry.path,
      packages: {
        for (final p in (overlay.config['packages']! as List).cast<Map<String, Object?>>())
          p['name']! as String,
      },
    ));
  } finally {
    restoreManifest?.call();
    originals.forEach((file, bytes) {
      file.writeAsBytesSync(bytes);
      backups[file]!.deleteSync();
    });
  }
}

/// [manifest] with [packages] added to its dependencies (as `any`).
FlutterManifest withDependencies(FlutterManifest manifest, List<String> packages) {
  final yaml = manifest.toYaml();
  final doc = jsonDecode(jsonEncode(yaml)) as Map<String, Object?>;
  doc['dependencies'] = {
    ...?(doc['dependencies'] as Map<String, Object?>?),
    for (final p in packages) p: 'any',
  };
  // ignore: invalid_use_of_visible_for_testing_member
  return FlutterManifest.createFromString(jsonEncode(doc), logger: globals.logger) ??
      throwToolExit('Could not extend the manifest with ${packages.join(', ')}.');
}

Map<String, Object?> _json(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
