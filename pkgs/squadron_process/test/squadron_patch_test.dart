@TestOn('vm')
library;

import 'dart:io';

import 'package:patched_source/patched_source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _oldPath = '.dart_tool/squadron_process/squadron-4ab7f15a5d6d';

void main() {
  final packageRoot = Directory.current.absolute;
  late String repository;
  late String newCommit;
  late String newPath;
  late Directory suite;
  late Directory upstream;
  late Directory fixture;
  late Map<String, String> environment;

  Future<String> git(Directory directory, List<String> args) async {
    final result = await Process.run('git', ['-C', directory.path, ...args]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (result.stdout as String).trim();
  }

  Future<ProcessResult> runPatch() => Process.run(
    'dart',
    ['run', 'squadron_process:squadron_patch', fixture.path],
    workingDirectory: packageRoot.path,
    environment: environment,
  );

  setUpAll(() async {
    final pin = await readPatchPin(
      File(
        p.join(packageRoot.path, '..', '..', 'third_party', 'squadron', 'PIN'),
      ),
    );
    repository = pin['repo']!;
    newCommit = pin['commit']!;
    newPath = '.dart_tool/third_party/squadron-${newCommit.substring(0, 12)}';
    suite = await Directory.systemTemp.createTemp('squadron patch fixtures ');
    upstream = await Directory(p.join(suite.path, 'upstream')).create();
    await git(upstream, ['init', '-q']);
    await git(upstream, [
      'fetch',
      '-q',
      '--depth',
      '1',
      Platform.environment['SQUADRON_TEST_REPOSITORY'] ?? repository,
      newCommit,
    ]);
    // The command still checks the literal origin recorded in the PIN.
    // Only network transport is redirected to this local fixture repository.
    environment = {
      'GIT_CONFIG_COUNT': '1',
      'GIT_CONFIG_KEY_0': 'url.${upstream.uri}.insteadOf',
      'GIT_CONFIG_VALUE_0': repository,
    };
  });
  tearDownAll(() async => suite.delete(recursive: true));
  setUp(() async {
    fixture = await suite.createTemp('workspace with spaces ');
    await File(p.join(fixture.path, 'pubspec.yaml'))
        .writeAsString('name: fixture\n');
  });
  tearDown(() async => fixture.delete(recursive: true));

  test('uses the new cache and ignores the old directory', () async {
    final old = await Directory(p.join(fixture.path, _oldPath))
        .create(recursive: true);
    final owner = File(p.join(old.path, 'owner.txt'));
    await owner.writeAsString('untouched old cache');
    await File(p.join(fixture.path, 'pubspec_overrides.yaml'))
        .writeAsString('# retained comment\ndependency_overrides: {}\n');
    final result = await runPatch();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('($newCommit)'));
    final file = File(p.join(fixture.path, 'pubspec_overrides.yaml'));
    final contents = await file.readAsString();
    expect(
      loadYaml(contents)['dependency_overrides']['squadron']['path'],
      newPath,
    );
    expect(contents, contains('# retained comment'));
    expect(await owner.readAsString(), 'untouched old cache');
    final source = Directory(p.join(fixture.path, newPath));
    expect(
      await File(p.join(source.path, '.patched_source.json')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(source.path, 'lib/src/_impl/web/_entry_point_uri.dart'))
          .readAsString(),
      contains('globalThis.squadronWorkerScriptUrl=workerUri;'),
    );
    final second = await runPatch();
    expect(second.exitCode, 0, reason: '${second.stderr}');
    expect(await file.readAsString(), contents);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('custom override is byte-identical on refusal', () async {
    final file = File(p.join(fixture.path, 'pubspec_overrides.yaml'));
    const contents =
        '# my source\ndependency_overrides:\n  squadron:\n    path: ../custom squadron\n';
    await file.writeAsString(contents);
    final result = await runPatch();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('squadron'));
    expect(await file.readAsString(), contents);
    expect(await Directory(p.join(fixture.path, newPath)).exists(), isFalse);
  });

  test(
    'old-path overrides are refused without touching their source',
    () async {
      final old = await Directory(p.join(fixture.path, _oldPath))
          .create(recursive: true);
      final owner = File(p.join(old.path, 'owner.txt'));
      await owner.writeAsString('owner content');
      await File(p.join(fixture.path, 'pubspec_overrides.yaml')).writeAsString(
        'dependency_overrides:\n  squadron:\n    path: $_oldPath\n',
      );
      final overrides = File(p.join(fixture.path, 'pubspec_overrides.yaml'));
      final before = await overrides.readAsBytes();
      final result = await runPatch();
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('conflicting override for squadron'));
      expect(await owner.readAsString(), 'owner content');
      expect(await overrides.readAsBytes(), before);
      expect(await Directory(p.join(fixture.path, newPath)).exists(), isFalse);
    },
  );

  test('unstamped new destination is refused without adopting it', () async {
    final source = await Directory(p.join(fixture.path, newPath))
        .create(recursive: true);
    final owner = File(p.join(source.path, 'owner.txt'));
    await owner.writeAsString('owner content');
    final result = await runPatch();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains(source.path));
    expect(await owner.readAsString(), 'owner content');
    expect(
      await File(p.join(source.path, '.patched_source.json')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(fixture.path, 'pubspec_overrides.yaml')).exists(),
      isFalse,
    );
  });
}
