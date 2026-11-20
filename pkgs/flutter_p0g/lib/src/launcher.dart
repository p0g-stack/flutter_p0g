import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'launcher_sdk.dart';

/// Bumped when the host layout or build steps change, so no older host is reused.
const _hostSchema = 1;
const _snapshotName = 'flutter_p0g.dill';
const _toolPackage = 'flutter_p0g_tool';

/// Runs flutter_p0g: resolves the tool package against the selected stock
/// Flutter SDK, builds it once per SDK, checkout and source state, and runs
/// it with this process's stdio. Returns the tool's exit code.
Future<int> launch(List<String> args) async {
  try {
    final launcherRoot = await _launcherRoot();
    final supported = _supportedFlutter(launcherRoot);
    final sdk = FlutterSdk.locate();
    await sdk.requireVersion(supported);
    final toolRoot = p.join(p.dirname(launcherRoot), _toolPackage);
    final (host, use) = await _prepareHost(sdk, launcherRoot, toolRoot);
    try {
      return await _runTool(sdk, host, args);
    } finally {
      await use.close();
    }
  } on LaunchException catch (e) {
    stderr.writeln('flutter_p0g: ${e.message}');
    return 1;
  }
}

/// This package's root: `<checkout>/pkgs/flutter_p0g`.
Future<String> _launcherRoot() async {
  final self = await Isolate.resolvePackageUri(Uri.parse('package:flutter_p0g/src/launcher.dart'));
  if (self == null || !self.isScheme('file')) {
    throw LaunchException('cannot locate package:flutter_p0g; run it from its package.');
  }
  return p.dirname(p.dirname(p.dirname(self.toFilePath())));
}

/// The one Flutter release the launcher supports: its `environment.flutter`.
String _supportedFlutter(String launcherRoot) {
  final pubspec = _readYaml(p.join(launcherRoot, 'pubspec.yaml'));
  if (pubspec case {'environment': {'flutter': final String version}}) return version;
  throw LaunchException('$launcherRoot/pubspec.yaml has no environment.flutter version.');
}

YamlMap _readYaml(String path) {
  final file = File(path);
  if (!file.existsSync()) throw LaunchException('$path not found.');
  final value = loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
  if (value is! YamlMap) throw LaunchException('$path is not a YAML map.');
  return value;
}

/// Returns a built host and a shared lock on it, held while the tool runs
/// so no other launcher prunes it.
Future<(String, RandomAccessFile)> _prepareHost(
  FlutterSdk sdk,
  String launcherRoot,
  String toolRoot,
) async {
  final checkout = Directory(launcherRoot).resolveSymbolicLinksSync();
  final group = p.join(
    _hostCache(),
    _hash((sink) {
      _field(sink, 'flutter_p0g-host/$_hostSchema');
      _field(sink, sdk.canonicalRoot);
      _field(sink, checkout);
    }).substring(0, 16),
  );
  Directory(group).createSync(recursive: true);

  for (var attempt = 0; attempt < 3; attempt++) {
    final pubspec = _hostPubspec(sdk, toolRoot);
    final key = _contentKey(sdk, checkout, toolRoot, pubspec);
    final host = p.join(group, key);
    final use = await File('$host.lock').open(mode: FileMode.append);
    var keep = false;
    try {
      await use.lock(FileLock.blockingShared);
      if (_isBuilt(host) ||
          await _build(sdk, group, host, pubspec, toolRoot, () {
            return _contentKey(sdk, checkout, toolRoot, _hostPubspec(sdk, toolRoot)) == key;
          })) {
        keep = true;
        return (host, use);
      }
    } finally {
      if (!keep) await use.close();
    }
  }
  throw LaunchException('$toolRoot kept changing while it was built; try again.');
}

bool _isBuilt(String host) => File(p.join(host, _snapshotName)).existsSync();

/// Builds [host] under the group's exclusive lock and publishes its snapshot
/// atomically. Returns false, publishing nothing, when the sources changed
/// during the build.
Future<bool> _build(
  FlutterSdk sdk,
  String group,
  String host,
  String pubspec,
  String toolRoot,
  bool Function() unchanged,
) async {
  final lock = await File(p.join(group, 'build.lock')).open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    if (_isBuilt(host)) return true;

    stderr.writeln('flutter_p0g: building the tool for Flutter ${sdk.version}…');
    final dir = Directory(host);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    File(p.join(host, 'pubspec.yaml')).writeAsStringSync(pubspec);

    final environment = {'FLUTTER_ROOT': sdk.root};
    final offline = await runProcess(
      sdk.dartWrapper,
      const ['pub', 'get', '--offline'],
      workingDirectory: host,
      environment: environment,
      onStdout: (_) {},
      onStderr: (_) {},
    );
    if (offline != 0) {
      final online = await runProcess(
        sdk.dartWrapper,
        const ['pub', 'get'],
        workingDirectory: host,
        environment: environment,
        onStdout: stderr.add,
        onStderr: stderr.add,
      );
      if (online != 0) throw LaunchException('`dart pub get` failed in $host (exit $online).');
    }

    final snapshot = p.join(host, _snapshotName);
    final partial = p.join(host, 'partial.dill');
    final compiled = await runProcess(
      sdk.dartWrapper,
      [
        'compile',
        'kernel',
        '--no-link-platform',
        '--packages=${_packageConfig(host)}',
        '--output=$partial',
        p.join(toolRoot, 'bin', 'flutter_p0g.dart'),
      ],
      workingDirectory: host,
      environment: environment,
      onStdout: stderr.add,
      onStderr: stderr.add,
    );
    if (compiled != 0) throw LaunchException('compiling $toolRoot failed (exit $compiled).');

    if (!unchanged()) {
      dir.deleteSync(recursive: true);
      return false;
    }
    File(partial).renameSync(snapshot);
    await _pruneSiblings(group, host);
    return true;
  } finally {
    await lock.close();
  }
}

/// Deletes the group's other hosts that no running launcher holds.
Future<void> _pruneSiblings(String group, String keep) async {
  for (final entry in Directory(group).listSync()) {
    if (entry is! Directory || p.equals(entry.path, keep)) continue;
    final use = await File('${entry.path}.lock').open(mode: FileMode.append);
    try {
      await use.lock(FileLock.exclusive);
      entry.deleteSync(recursive: true);
    } on FileSystemException {
      // In use; a later build prunes it.
    } finally {
      await use.close();
    }
  }
}

String _packageConfig(String host) => p.join(host, '.dart_tool', 'package_config.json');

/// The host package: the tool against this SDK's flutter_tools, carrying the
/// tool's own overrides, which pub honors only in the root package.
String _hostPubspec(FlutterSdk sdk, String toolRoot) {
  final tool = _readYaml(p.join(toolRoot, 'pubspec.yaml'));
  final dartSdk = switch (tool) {
    {'environment': {'sdk': final String constraint}} => constraint,
    _ => throw LaunchException('$toolRoot/pubspec.yaml has no environment.sdk.'),
  };
  final overrides = <String, Object?>{};
  if (tool['dependency_overrides'] case final Map own) {
    for (final MapEntry(:key, :value) in own.entries) {
      overrides['$key'] = _absolutePath(_plain(value), toolRoot);
    }
  }
  overrides['flutter_tools'] = {'path': sdk.flutterTools};
  // JSON is YAML, and quotes any path.
  return const JsonEncoder.withIndent('  ').convert({
    'name': 'flutter_p0g_host',
    'publish_to': 'none',
    'environment': {'sdk': dartSdk},
    'dependencies': {
      _toolPackage: {'path': toolRoot},
    },
    'dependency_overrides': overrides,
  });
}

Object? _plain(Object? yaml) => switch (yaml) {
  final Map map => {for (final MapEntry(:key, :value) in map.entries) '$key': _plain(value)},
  final List list => [for (final value in list) _plain(value)],
  _ => yaml,
};

Object? _absolutePath(Object? dependency, String base) {
  if (dependency case final Map<String, Object?> map) {
    if (map['path'] case final String path when p.isRelative(path)) {
      return {...map, 'path': p.normalize(p.join(base, path))};
    }
  }
  return dependency;
}

/// Hosts live in the user's cache, `$XDG_CACHE_HOME/p0g/tool`.
String _hostCache() {
  final env = Platform.environment;
  final xdg = env['XDG_CACHE_HOME'];
  final String base;
  if (xdg != null && xdg.isNotEmpty) {
    base = xdg;
  } else if (Platform.isWindows) {
    base = env['LOCALAPPDATA'] ?? (throw LaunchException('LOCALAPPDATA is not set.'));
  } else {
    base = p.join(env['HOME'] ?? (throw LaunchException('HOME is not set.')), '.cache');
  }
  return p.join(p.normalize(p.absolute(base)), 'p0g', 'tool');
}

/// Identifies a host by everything its snapshot and package config depend
/// on: SDK revision and location, checkout, pub cache, host pubspec, and the
/// sources of the tool and its path dependencies.
String _contentKey(FlutterSdk sdk, String checkout, String toolRoot, String pubspec) {
  return _hash((sink) {
    _field(sink, 'flutter_p0g-host/$_hostSchema');
    _field(sink, sdk.revision);
    _field(sink, sdk.canonicalRoot);
    _field(sink, checkout);
    _field(sink, _pubCache());
    _field(sink, pubspec);
    for (final root in _sourceRoots(toolRoot)) {
      _field(sink, root);
      _hashTree(sink, Directory(root), '');
    }
  }).substring(0, 32);
}

/// The pub cache `dart pub get` uses, as pub picks it.
String _pubCache() {
  final env = Platform.environment;
  final configured = env['PUB_CACHE'];
  final String path;
  if (configured != null && configured.isNotEmpty) {
    path = configured;
  } else if (Platform.isWindows) {
    path = p.join(env['LOCALAPPDATA'] ?? '', 'Pub', 'Cache');
  } else {
    path = p.join(env['HOME'] ?? '', '.pub-cache');
  }
  return p.normalize(p.absolute(path));
}

/// The tool package and its transitive `path:` dependencies and overrides.
List<String> _sourceRoots(String toolRoot) {
  final roots = <String>[];
  final pending = [Directory(toolRoot).resolveSymbolicLinksSync()];
  while (pending.isNotEmpty) {
    final root = pending.removeLast();
    if (roots.contains(root)) continue;
    roots.add(root);
    final pubspec = _readYaml(p.join(root, 'pubspec.yaml'));
    for (final section in const ['dependencies', 'dependency_overrides']) {
      if (pubspec[section] case final Map dependencies) {
        for (final dependency in dependencies.values) {
          if (dependency case {'path': final String path}) {
            final dir = Directory(p.join(root, path));
            if (!dir.existsSync()) throw LaunchException('$root depends on missing ${dir.path}.');
            pending.add(dir.resolveSymbolicLinksSync());
          }
        }
      }
    }
  }
  return roots;
}

/// Hashes a package's files, skipping hidden entries, top-level `build/` and
/// `test/`, and the machine-local lock and override files.
void _hashTree(Sink<List<int>> sink, Directory dir, String relative) {
  final entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
  for (final entry in entries) {
    final name = p.basename(entry.path);
    if (name.startsWith('.')) continue;
    final path = relative.isEmpty ? name : '$relative/$name';
    if (entry is Directory) {
      if (relative.isEmpty && (name == 'build' || name == 'test')) continue;
      _hashTree(sink, entry, path);
    } else if (entry is File) {
      if (relative.isEmpty && (name == 'pubspec.lock' || name == 'pubspec_overrides.yaml')) {
        continue;
      }
      _field(sink, path);
      final bytes = entry.readAsBytesSync();
      sink
        ..add(utf8.encode('${bytes.length}\n'))
        ..add(bytes);
    }
  }
}

void _field(Sink<List<int>> sink, String value) {
  final bytes = utf8.encode(value);
  sink
    ..add(utf8.encode('${bytes.length}\n'))
    ..add(bytes);
}

String _hash(void Function(Sink<List<int>>) write) {
  final result = _DigestSink();
  final sink = sha256.startChunkedConversion(result);
  write(sink);
  sink.close();
  return result.digest.toString();
}

final class _DigestSink implements Sink<Digest> {
  late final Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// Runs the tool snapshot with this process's stdio and returns its exit
/// code. Terminal interrupts reach the tool directly; termination requests
/// to the launcher are passed on so the tool can clean up.
Future<int> _runTool(FlutterSdk sdk, String host, List<String> args) async {
  final process = await Process.start(
    sdk.dartVm,
    ['--packages=${_packageConfig(host)}', p.join(host, _snapshotName), ...args],
    environment: {'FLUTTER_ROOT': sdk.root},
    mode: ProcessStartMode.inheritStdio,
  );
  final signals = [
    ProcessSignal.sigint.watch().listen((_) {}),
    if (!Platform.isWindows)
      for (final signal in const [ProcessSignal.sigterm, ProcessSignal.sighup])
        signal.watch().listen(process.kill),
  ];
  try {
    final code = await process.exitCode;
    return code < 0 ? 128 - code : code;
  } finally {
    for (final subscription in signals) {
      await subscription.cancel();
    }
  }
}
