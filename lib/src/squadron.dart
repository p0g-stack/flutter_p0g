import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import 'p0g_cache.dart';

/// squadron_process carries its own Squadron patch series
/// (`third_party/squadron/`) and a tool that materializes it under the
/// workspace's `.dart_tool/` and points `pubspec_overrides.yaml` at it
/// (`dart run squadron_process:squadron_patch <root>`). flutter_p0g runs
/// that tool, then `pub get`, so apps don't have to; the series stays
/// squadron_process's.
const kSquadronProcess = 'squadron_process';

/// Whether [root]'s `pubspec_overrides.yaml` already overrides squadron.
@visibleForTesting
bool overridesSquadron(String? overridesYaml) {
  if (overridesYaml == null) return false;
  final doc = loadYaml(overridesYaml);
  return doc is YamlMap &&
      doc['dependency_overrides'] is YamlMap &&
      (doc['dependency_overrides'] as YamlMap).containsKey('squadron');
}

/// The workspace member (or [root] itself) that depends on squadron_process
/// directly, where `dart run squadron_process:…` resolves.
@visibleForTesting
Directory? squadronProcessUser(Directory root) {
  bool dependsOn(Directory dir) {
    final pubspec = dir.childFile('pubspec.yaml');
    if (!pubspec.existsSync()) return false;
    final doc = loadYaml(pubspec.readAsStringSync());
    if (doc is! YamlMap) return false;
    final deps = doc['dependencies'];
    return deps is YamlMap && deps.containsKey(kSquadronProcess);
  }

  if (dependsOn(root)) return root;
  final doc = loadYaml(root.childFile('pubspec.yaml').readAsStringSync());
  final members = doc is YamlMap && doc['workspace'] is YamlList
      ? (doc['workspace'] as YamlList).cast<String>()
      : const <String>[];
  for (final m in members) {
    final dir = root.childDirectory(m);
    if (dependsOn(dir)) return dir;
  }
  return null;
}

/// The workspace root above [project] (or [project]), from its package config.
Directory workspaceRoot(Directory project) =>
    findPackageConfigFile(project)?.parent.parent ?? project;

/// Patches Squadron for [project] when it uses squadron_process and nothing
/// overrides squadron yet ([force]: always). Returns whether it ran.
Future<bool> ensurePatchedSquadron(Directory project, {bool force = false}) async {
  final root = workspaceRoot(project);
  final overrides = root.childFile('pubspec_overrides.yaml');
  final user = squadronProcessUser(root);
  if (user == null) {
    if (force) throwToolExit('No package in ${root.path} depends on $kSquadronProcess.');
    return false;
  }
  if (!force && overridesSquadron(overrides.existsSync() ? overrides.readAsStringSync() : null)) {
    return false;
  }
  globals.printStatus("Patching Squadron with $kSquadronProcess's series...");
  Future<void> run(List<String> cmd, Directory cwd) async {
    final code = await globals.processUtils.stream(cmd, workingDirectory: cwd.path);
    if (code != 0) throwToolExit('${cmd.take(3).join(' ')} failed (exit $code).');
  }

  final pubGet = [globals.fs.path.join(Cache.flutterRoot!, 'bin', 'flutter'), 'pub', 'get'];
  // squadron_process must resolve before its tool can run.
  if (findPackageConfigFile(root) == null) await run(pubGet, root);
  await run([dartBinary(), 'run', '$kSquadronProcess:squadron_patch', root.path], user);
  await run(pubGet, root);
  return true;
}
