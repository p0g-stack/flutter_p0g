import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A launcher failure the user can act on; printed without a stack trace.
final class LaunchException implements Exception {
  LaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A stock Flutter SDK checkout, pinned to one framework revision.
final class FlutterSdk {
  FlutterSdk._(this.root, this.canonicalRoot);

  /// The root as found: `FLUTTER_ROOT` for the tool and the SDK's scripts.
  final String root;

  /// [root] with symlinks resolved, identifying the SDK in cache keys.
  final String canonicalRoot;

  late final String version;
  late final String revision;

  /// `bin/dart`, which bootstraps the SDK's Dart before running it.
  String get dartWrapper => p.join(root, 'bin', Platform.isWindows ? 'dart.bat' : 'dart');

  String get _flutterWrapper => p.join(root, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter');

  /// The SDK's Dart VM itself, valid once [requireVersion] bootstrapped it.
  String get dartVm =>
      p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', Platform.isWindows ? 'dart.exe' : 'dart');

  String get flutterTools => p.join(root, 'packages', 'flutter_tools');

  /// Finds the SDK: `FLUTTER_ROOT`, then the SDK whose Dart runs this
  /// launcher, then the `flutter` on `PATH`.
  static FlutterSdk locate() {
    final env = Platform.environment['FLUTTER_ROOT'];
    if (env != null && env.isNotEmpty) {
      return _at(env) ?? (throw LaunchException('FLUTTER_ROOT=$env is not a Flutter SDK.'));
    }

    // <root>/bin/cache/dart-sdk/bin/dart
    final dartBin = p.dirname(Platform.resolvedExecutable);
    final dartSdk = p.dirname(dartBin);
    final cache = p.dirname(dartSdk);
    if (p.basename(dartBin) == 'bin' &&
        p.basename(dartSdk) == 'dart-sdk' &&
        p.basename(cache) == 'cache') {
      if (_at(p.dirname(p.dirname(cache))) case final sdk?) return sdk;
    }

    final flutter = _flutterOnPath();
    if (flutter == null) {
      throw LaunchException('No Flutter SDK found: set FLUTTER_ROOT or put flutter on PATH.');
    }
    final resolved = File(flutter).resolveSymbolicLinksSync();
    return _at(p.dirname(p.dirname(resolved))) ??
        (throw LaunchException('$flutter is not in a Flutter SDK; set FLUTTER_ROOT.'));
  }

  static FlutterSdk? _at(String path) {
    final root = p.normalize(p.absolute(path));
    final sdk = FlutterSdk._(root, root);
    if (!File(sdk._flutterWrapper).existsSync() ||
        !File(p.join(sdk.flutterTools, 'pubspec.yaml')).existsSync()) {
      return null;
    }
    return FlutterSdk._(root, Directory(root).resolveSymbolicLinksSync());
  }

  static String? _flutterOnPath() {
    final names = Platform.isWindows ? const ['flutter.bat', 'flutter.exe'] : const ['flutter'];
    final path = Platform.environment['PATH'] ?? '';
    for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        final candidate = p.join(dir, name);
        if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.file) return candidate;
      }
    }
    return null;
  }

  /// Reads the SDK's version and actual revision, refreshing Flutter's
  /// version file and Dart through `flutter --version` when they are stale or
  /// missing, and requires [supported] exactly.
  Future<void> requireVersion(String supported) async {
    final head = await _gitHead();
    var info = _readVersionFile();
    if (info == null || (head != null && info.revision != head) || !File(dartVm).existsSync()) {
      info = await _flutterVersion();
    }
    if (head != null && info.revision != head) {
      throw LaunchException(
        'Flutter at $root reports revision ${info.revision}, but its checkout is at $head.',
      );
    }
    if (info.version != supported) {
      throw LaunchException(
        'requires Flutter $supported, but $root is Flutter ${info.version} (${info.revision}). '
        'Set FLUTTER_ROOT to a Flutter $supported SDK.',
      );
    }
    version = info.version;
    revision = info.revision;
  }

  /// The checkout's HEAD, or null when the SDK is not its own Git checkout.
  Future<String?> _gitHead() async {
    final ProcessResult result;
    try {
      result = await Process.run('git', ['-C', root, 'rev-parse', '--show-toplevel', 'HEAD']);
    } on ProcessException {
      return null;
    }
    if (result.exitCode != 0) return null;
    final lines = LineSplitter.split(result.stdout as String).toList();
    if (lines.length != 2) return null;
    final top = Directory(lines[0]).resolveSymbolicLinksSync();
    return p.equals(top, canonicalRoot) ? lines[1].trim() : null;
  }

  _VersionInfo? _readVersionFile() {
    final file = File(p.join(root, 'bin', 'cache', 'flutter.version.json'));
    if (!file.existsSync()) return null;
    try {
      return _VersionInfo.parse(file.readAsStringSync());
    } on FormatException {
      return null;
    }
  }

  Future<_VersionInfo> _flutterVersion() async {
    final out = <int>[];
    final code = await runProcess(
      _flutterWrapper,
      const ['--version', '--machine'],
      onStdout: out.addAll,
      onStderr: stderr.add,
    );
    final text = utf8.decode(out, allowMalformed: true);
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (code == 0 && start >= 0 && end > start) {
      try {
        return _VersionInfo.parse(text.substring(start, end + 1));
      } on FormatException {
        // Reported below.
      }
    }
    throw LaunchException('`$_flutterWrapper --version --machine` failed (exit $code).');
  }
}

final class _VersionInfo {
  _VersionInfo(this.version, this.revision);

  factory _VersionInfo.parse(String json) {
    final value = jsonDecode(json);
    if (value case {
      'frameworkVersion': final String version,
      'frameworkRevision': final String revision,
    }) {
      return _VersionInfo(version, revision);
    }
    throw const FormatException('no frameworkVersion/frameworkRevision');
  }

  final String version;
  final String revision;
}

/// Runs [executable] with closed stdin, handing its output to the callbacks.
Future<int> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  required void Function(List<int>) onStdout,
  required void Function(List<int>) onStderr,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: Platform.isWindows,
  );
  unawaited(process.stdin.close());
  final output = [
    process.stdout.listen(onStdout).asFuture<void>(),
    process.stderr.listen(onStderr).asFuture<void>(),
  ];
  final code = await process.exitCode;
  await Future.wait(output);
  return code;
}
