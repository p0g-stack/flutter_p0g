// Blackbox tests for the launcher: they run bin/flutter_p0g.dart from a
// copied checkout against a synthetic Flutter SDK, whose dart-sdk is the real
// one running this test, and a fake flutter_p0g_tool that reports what it saw.
@TestOn('vm && !windows')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _reportPrefix = 'FAKE_TOOL_REPORT ';

void main() {
  test('passes arguments, stdio, cwd and exit code through to the tool', () async {
    final f = await _Fixture.create();
    final args = ['build', 'webui', '--define=a b', '--', 'ünïcode', ''];
    final run = await f.launch([...args, '--exit=7'], stdinText: 'from stdin\n');

    expect(run.exitCode, 7, reason: run.describe());
    final report = run.report;
    expect(report['args'], [...args, '--exit=7']);
    expect(report['stdin'], 'from stdin');
    expect(report['cwd'], f.cwd.resolveSymbolicLinksSync());
    expect(run.stderr, contains('fake tool stderr'));

    final ok = await f.launch(['doctor']);
    expect(ok.exitCode, 0, reason: ok.describe());
    expect(ok.report['args'], ['doctor']);
  });

  test('runs the tool on the original SDK with the host package config', () async {
    final f = await _Fixture.create();
    final run = await f.launch(['x']);

    expect(run.exitCode, 0, reason: run.describe());
    final report = run.report;
    expect(report['FLUTTER_ROOT'], f.sdk.path);
    expect(
      report['flutter_tools'],
      '${p.toUri(p.join(f.sdk.path, 'packages', 'flutter_tools', 'lib'))}/',
    );
    expect(report['flutter_p0g_tool'], '${p.toUri(p.join(f.tool.path, 'lib'))}/');
    expect(report['flutter_tools_marker'], 'tools-1');
    expect(report['patched_source_marker'], 'patched-1');
    final config = report['packageConfig'] as String?;
    expect(config, isNotNull, reason: 'Isolate.packageConfig must be set');
    final configPath = Uri.parse(config!).toFilePath();
    expect(p.basename(configPath), 'package_config.json');
    expect(
      p.isWithin(p.join(f.cache.path, 'p0g', 'tool'), configPath),
      isTrue,
      reason: 'the host package lives in the user cache, not in the checkout',
    );
  });

  test('hands the tool FLUTTER_ROOT as given, without resolving symlinks', () async {
    final f = await _Fixture.create();
    final link = Link(p.join(f.root.path, 'sdk link'))..createSync(f.sdk.path);
    final run = await f.launch(['x'], flutterRoot: link.path);

    expect(run.exitCode, 0, reason: run.describe());
    expect(run.report['FLUTTER_ROOT'], link.path);
    final tools = Uri.parse(run.report['flutter_tools']! as String).toFilePath();
    expect(
      Directory(tools).resolveSymbolicLinksSync(),
      p.join(f.sdk.path, 'packages', 'flutter_tools', 'lib'),
    );
  });

  test('refuses an SDK that is not the pinned Flutter version', () async {
    final f = await _Fixture.create(sdkVersion: '3.49.0');
    final run = await f.launch(['doctor']);

    expect(run.exitCode, 1, reason: run.describe());
    expect(run.hasReport, isFalse, reason: 'the tool must not start');
    expect(
      run.stderr,
      allOf(
        startsWith('flutter_p0g: '),
        contains('requires Flutter ${f.pinned}'),
        contains('3.49.0'),
      ),
    );
  });

  test('reads the pin from the launcher pubspec at run time', () async {
    final f = await _Fixture.create();
    expect((await f.launch(['x'])).exitCode, 0);

    final pubspec = File(p.join(f.launcher.path, 'pubspec.yaml'));
    pubspec.writeAsStringSync(
      pubspec.readAsStringSync().replaceFirstMapped(
        RegExp(r'^([ \t]+flutter:[ \t]*).*$', multiLine: true),
        (m) => '${m[1]}9.9.9',
      ),
    );
    final run = await f.launch(['x']);
    expect(run.exitCode, 1, reason: run.describe());
    expect(run.hasReport, isFalse);
    expect(run.stderr, allOf(contains('requires Flutter 9.9.9'), contains(f.pinned)));
  });

  test('reuses the snapshot until the SDK revision or tool source changes', () async {
    final f = await _Fixture.create();
    Future<Map<String, Object?>> report() async {
      final run = await f.launch(['x']);
      expect(run.exitCode, 0, reason: run.describe());
      return run.report;
    }

    expect((await report())['flutter_tools_marker'], 'tools-1');

    // Same revision: flutter_tools is not looked at again, so the old
    // snapshot (and the old marker compiled into it) still runs.
    f.setFlutterToolsMarker('tools-2');
    expect((await report())['flutter_tools_marker'], 'tools-1');

    f.writeSdkVersion(revision: 'b' * 40);
    expect((await report())['flutter_tools_marker'], 'tools-2');

    f.setToolMarker('tool-2');
    expect((await report())['tool_marker'], 'tool-2');

    f.setPatchedSourceMarker('patched-2');
    expect((await report())['patched_source_marker'], 'patched-2');
  });

  test('bootstraps concurrently from a cold cache', () async {
    final f = await _Fixture.create();
    final runs = await Future.wait([
      for (var i = 0; i < 3; i++) f.launch(['run-$i']),
    ]);
    for (final (i, run) in runs.indexed) {
      expect(run.exitCode, 0, reason: run.describe());
      expect(run.report['args'], ['run-$i']);
    }
  });
}

class _Fixture {
  _Fixture(this.root, this.pinned);

  final Directory root;
  final String pinned;

  Directory get repo => Directory(p.join(root.path, 'repo'));
  Directory get launcher => Directory(p.join(repo.path, 'pkgs', 'flutter_p0g'));
  Directory get tool => Directory(p.join(repo.path, 'pkgs', 'flutter_p0g_tool'));
  Directory get patchedSource => Directory(p.join(repo.path, 'pkgs', 'patched_source'));
  Directory get sdk => Directory(p.join(root.path, 'flutter sdk'));
  Directory get cwd => Directory(p.join(root.path, 'work dir'));
  Directory get cache => Directory(p.join(root.path, 'xdg cache'));
  File get _launcherConfig => File(p.join(root.path, 'launcher_package_config.json'));

  /// A checkout and SDK under a fresh temp dir. The SDK reports [sdkVersion]
  /// (default: the launcher's pin).
  static Future<_Fixture> create({String? sdkVersion}) async {
    final root = (await Directory.systemTemp.createTemp('flutter_p0g_launcher_'))
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).delete(recursive: true));

    final source = await _launcherSource();
    final pubspec =
        loadYaml(File(p.join(source.path, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    final pinned = (pubspec['environment'] as YamlMap)['flutter'].toString();
    final f = _Fixture(Directory(root), pinned);

    _copyDir(Directory(p.join(source.path, 'bin')), Directory(p.join(f.launcher.path, 'bin')));
    _copyDir(Directory(p.join(source.path, 'lib')), Directory(p.join(f.launcher.path, 'lib')));
    File(p.join(source.path, 'pubspec.yaml')).copySync(p.join(f.launcher.path, 'pubspec.yaml'));
    await f._writeLauncherConfig(source);

    f._writeTool();
    f._writeSdk();
    f.writeSdkVersion(version: sdkVersion ?? pinned);
    f.cwd.createSync();
    return f;
  }

  Future<_Run> launch(List<String> args, {String stdinText = '', String? flutterRoot}) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--packages=${_launcherConfig.path}',
        p.join(launcher.path, 'bin', 'flutter_p0g.dart'),
        ...args,
      ],
      workingDirectory: cwd.path,
      environment: {'FLUTTER_ROOT': flutterRoot ?? sdk.path, 'XDG_CACHE_HOME': cache.path},
    );
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(stdinText);
    await process.stdin.close();
    return _Run(await process.exitCode, await out, await err);
  }

  void writeSdkVersion({String? version, String? revision}) {
    final file = File(p.join(sdk.path, 'bin', 'cache', 'flutter.version.json'));
    final old = file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as Map<String, Object?>
        : null;
    version ??= old!['frameworkVersion']! as String;
    final dart = Platform.version.split(' ').first;
    file.writeAsStringSync(
      jsonEncode({
        'frameworkVersion': version,
        'flutterVersion': version,
        'channel': 'stable',
        'repositoryUrl': 'https://github.com/flutter/flutter.git',
        'frameworkRevision': revision ?? 'a' * 40,
        'frameworkCommitDate': '2026-11-09 08:50:21 -0800',
        'engineRevision': 'c' * 40,
        'dartSdkVersion': dart,
      }),
    );
    File(p.join(sdk.path, 'version')).writeAsStringSync('$version\n');
  }

  void setFlutterToolsMarker(String marker) => _writeMarker(
    p.join(sdk.path, 'packages', 'flutter_tools', 'lib', 'flutter_tools.dart'),
    marker,
  );
  void setToolMarker(String marker) =>
      _writeMarker(p.join(tool.path, 'lib', 'src', 'marker.dart'), marker);
  void setPatchedSourceMarker(String marker) =>
      _writeMarker(p.join(patchedSource.path, 'lib', 'patched_source.dart'), marker);

  void _writeMarker(String path, String marker) => _write(path, "const marker = '$marker';\n");

  /// The launcher's own dependencies, from this test's package config, with
  /// package:flutter_p0g pointing at the copy.
  Future<void> _writeLauncherConfig(Directory source) async {
    final configUri = (await Isolate.packageConfig)!;
    final config = jsonDecode(File.fromUri(configUri).readAsStringSync()) as Map<String, Object?>;
    for (final package in (config['packages']! as List).cast<Map<String, Object?>>()) {
      package['rootUri'] = package['name'] == 'flutter_p0g'
          ? Uri.directory(launcher.path).toString()
          : configUri.resolve(package['rootUri']! as String).toString();
    }
    _write(_launcherConfig.path, jsonEncode(config));
  }

  void _writeTool() {
    _write(p.join(patchedSource.path, 'pubspec.yaml'), '''
name: patched_source
publish_to: none
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    setPatchedSourceMarker('patched-1');

    _write(p.join(tool.path, 'pubspec.yaml'), '''
name: flutter_p0g_tool
publish_to: none
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter_tools:
    sdk: flutter
  patched_source:
    path: ../patched_source
''');
    setToolMarker('tool-1');
    _write(p.join(tool.path, 'bin', 'flutter_p0g.dart'), '''
import 'package:flutter_p0g_tool/src/executable.dart' as executable;

Future<void> main(List<String> arguments) => executable.main(arguments);
''');
    _write(p.join(tool.path, 'lib', 'src', 'executable.dart'), r'''
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_tools/flutter_tools.dart' as flutter_tools;
import 'package:patched_source/patched_source.dart' as patched_source;

import 'marker.dart' as tool;

Future<void> main(List<String> arguments) async {
  Future<String?> resolve(String package) async =>
      (await Isolate.resolvePackageUri(Uri.parse('package:$package/')))?.toString();
  final report = {
    'args': arguments,
    'stdin': stdin.readLineSync(),
    'cwd': Directory.current.resolveSymbolicLinksSync(),
    'FLUTTER_ROOT': Platform.environment['FLUTTER_ROOT'],
    'packageConfig': (await Isolate.packageConfig)?.toString(),
    'flutter_tools': await resolve('flutter_tools'),
    'flutter_p0g_tool': await resolve('flutter_p0g_tool'),
    'flutter_tools_marker': flutter_tools.marker,
    'patched_source_marker': patched_source.marker,
    'tool_marker': tool.marker,
  };
  stdout.writeln('FAKE_TOOL_REPORT ${jsonEncode(report)}');
  stderr.writeln('fake tool stderr');
  final code = arguments.where((a) => a.startsWith('--exit=')).map((a) => int.parse(a.substring(7)));
  await stdout.flush();
  exit(code.isEmpty ? 0 : code.last);
}
''');
  }

  /// `bin/cache/dart-sdk` is the real Dart SDK; `bin/dart` and `bin/flutter`
  /// are thin shims over it; `packages/flutter_tools` is a stub package.
  void _writeSdk() {
    final dartSdk = p.dirname(p.dirname(Platform.resolvedExecutable));
    Directory(p.join(sdk.path, 'bin', 'cache')).createSync(recursive: true);
    Link(p.join(sdk.path, 'bin', 'cache', 'dart-sdk')).createSync(dartSdk);
    _write(p.join(sdk.path, 'bin', 'internal', 'engine.version'), '${'c' * 40}\n');
    _executable(p.join(sdk.path, 'bin', 'dart'), r'''
#!/bin/sh
exec "$(dirname -- "$0")/cache/dart-sdk/bin/dart" "$@"
''');
    // Stock `flutter pub` is `dart pub` with FLUTTER_ROOT set; nothing else
    // of the flutter command is a launcher concern.
    _executable(p.join(sdk.path, 'bin', 'flutter'), r'''
#!/bin/sh
bin=$(cd -- "$(dirname -- "$0")" && pwd)
FLUTTER_ROOT=$(dirname -- "$bin")
export FLUTTER_ROOT
case "$1" in
  pub|--version) exec "$bin/cache/dart-sdk/bin/dart" "$@" ;;
esac
echo "fixture flutter: unsupported command: $*" >&2
exit 64
''');
    _write(p.join(sdk.path, 'packages', 'flutter_tools', 'pubspec.yaml'), '''
name: flutter_tools
publish_to: none
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    setFlutterToolsMarker('tools-1');
  }
}

class _Run {
  _Run(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  Iterable<String> get _reports =>
      LineSplitter.split(stdout).where((l) => l.startsWith(_reportPrefix));

  bool get hasReport => _reports.isNotEmpty;

  Map<String, Object?> get report {
    final reports = _reports.toList();
    expect(reports, hasLength(1), reason: describe());
    return jsonDecode(reports.single.substring(_reportPrefix.length)) as Map<String, Object?>;
  }

  String describe() => 'exit $exitCode\n--- stdout\n$stdout\n--- stderr\n$stderr';
}

Future<Directory> _launcherSource() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_p0g/'));
  return Directory(p.dirname(p.fromUri(lib!)));
}

void _copyDir(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final target = p.join(to.path, p.relative(entity.path, from: from.path));
    Directory(p.dirname(target)).createSync(recursive: true);
    entity.copySync(target);
  }
}

void _write(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _executable(String path, String contents) {
  _write(path, contents);
  final result = Process.runSync('chmod', ['+x', path]);
  if (result.exitCode != 0) throw StateError('chmod $path: ${result.stderr}');
}
