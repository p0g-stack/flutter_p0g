import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:patched_source/patched_source.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory repository;
  late Directory destination;
  late String commit;
  late File patch;

  Future<String> git(List<String> args, {Directory? cwd}) async {
    final result = await Process.run('git', ['-C', (cwd ?? repository).path, ...args]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return (result.stdout as String).trim();
  }

  Future<Directory> materialize({List<File>? patches}) => materializePatchedSource(
    destination: destination,
    repository: repository.path,
    commit: commit,
    patches: patches ?? [patch],
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('patched source test ');
    repository = await Directory(p.join(temp.path, 'repository')).create();
    destination = Directory(p.join(temp.path, 'installed'));
    await git(['init', '-q']);
    await File(p.join(repository.path, 'value.txt')).writeAsString('original\n');
    await File(p.join(repository.path, '.gitignore')).writeAsString('build/\n');
    await git(['add', '.']);
    await git([
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      '-c',
      'commit.gpgsign=false',
      'commit',
      '-qm',
      'fixture',
    ]);
    commit = await git(['rev-parse', 'HEAD']);
    patch = File(p.join(temp.path, '0001.patch'));
    await patch.writeAsString(
      'diff --git a/value.txt b/value.txt\n'
      '--- a/value.txt\n+++ b/value.txt\n@@ -1 +1 @@\n-original\n+patched\n',
    );
  });
  tearDown(() async => temp.delete(recursive: true));

  test('real patches, complete identity and exact reuse', () async {
    await materialize();
    final value = File(p.join(destination.path, 'value.txt'));
    expect(await value.readAsString(), 'patched\n');
    final stamp = File(p.join(destination.path, '.patched_source.json'));
    final recorded = jsonDecode(await stamp.readAsString()) as Map;
    expect(recorded.keys, ['schema', 'repository', 'commit', 'patches', 'patchedTree']);
    expect(recorded['schema'], 1);
    expect(recorded['repository'], repository.path);
    expect(recorded['commit'], commit);
    expect(recorded['patches'][0]['name'], '0001.patch');
    expect(recorded['patches'][0]['sha256'], matches(r'^[a-f0-9]{64}$'));
    final modified = await stamp.lastModified();
    await materialize();
    expect(await stamp.lastModified(), modified);
  });

  test('changed patch bytes rebuild, failed rebuild preserves installed stamp', () async {
    await materialize();
    await patch.writeAsString((await patch.readAsString()).replaceAll('+patched', '+changed'));
    await materialize();
    final stamp = File(p.join(destination.path, '.patched_source.json'));
    final saved = await stamp.readAsBytes();
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'changed\n');
    await patch.writeAsString('not a patch\n');
    await expectLater(materialize(), throwsStateError);
    expect(await stamp.readAsBytes(), saved);
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'changed\n');
  });

  test('failed fresh application never installs or stamps', () async {
    await patch.writeAsString('not a patch\n');
    await expectLater(materialize(), throwsStateError);
    expect(await destination.exists(), isFalse);
  });

  test('tracked and untracked owner edits are refused even for matching identity', () async {
    await materialize();
    final value = File(p.join(destination.path, 'value.txt'));
    await value.writeAsString('owner edit\n');
    await expectLater(materialize(), throwsStateError);
    expect(await value.readAsString(), 'owner edit\n');
    await value.writeAsString('patched\n');
    final extra = File(p.join(destination.path, 'owner.txt'));
    await extra.writeAsString('owner');
    await expectLater(materialize(), throwsStateError);
    expect(await extra.readAsString(), 'owner');
  });

  test('ignored build output does not prevent replacement', () async {
    await materialize();
    final build = await Directory(p.join(destination.path, 'build')).create();
    await File(p.join(build.path, 'generated')).writeAsString('output');
    await patch.writeAsString((await patch.readAsString()).replaceAll('+patched', '+changed'));
    await materialize();
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'changed\n');
  });

  test('unowned directory and symlink are preserved', () async {
    await destination.create();
    final owner = File(p.join(destination.path, 'owner'));
    await owner.writeAsString('keep');
    await expectLater(materialize(), throwsStateError);
    expect(await owner.readAsString(), 'keep');
    await destination.delete(recursive: true);
    await Link(destination.path).create(repository.path);
    await expectLater(materialize(), throwsStateError);
    expect(await Link(destination.path).target(), repository.path);
  });

  test('empty patch list and regular patch filename filtering', () async {
    await materialize(patches: []);
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'original\n');
    final ignored = await File(p.join(temp.path, 'README')).writeAsString('not a patch');
    final link = await Link(p.join(temp.path, 'linked.patch')).create(patch.path);
    await materialize(patches: [ignored, File(link.path)]);
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'original\n');
  });

  test('patch order is filename order, not argument order', () async {
    final second = File(p.join(temp.path, '0002.patch'));
    await second.writeAsString(
      (await patch.readAsString())
          .replaceAll('-original', '-patched')
          .replaceAll('+patched', '+second'),
    );
    await materialize(patches: [second, patch]);
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'second\n');
  });

  test('concurrent materialization serializes calls', () async {
    await Future.wait([materialize(), materialize(), materialize()]);
    expect(await File(p.join(destination.path, 'value.txt')).readAsString(), 'patched\n');
  });

  test('PIN requires repository and full commit, not tag or package', () async {
    final pin = File(p.join(temp.path, 'PIN'));
    await pin.writeAsString('# comment\nrepo=${repository.path}\ncommit=$commit\n');
    expect(await readPatchPin(pin), {'repo': repository.path, 'commit': commit});
    await pin.writeAsString('repo=${repository.path}\ncommit=$commit\npackage=\n');
    expect((await readPatchPin(pin))['package'], '');
    for (final invalid in [
      'repo=x\n',
      'commit=$commit\n',
      'repo=x\ncommit=abc\n',
      'repo=x\nrepo=y\ncommit=$commit\n',
    ]) {
      await pin.writeAsString(invalid);
      await expectLater(readPatchPin(pin), throwsFormatException);
    }
    await expectLater(
      readPatchPin(File(p.join(temp.path, 'missing-series', 'PIN'))),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('managed override migration preserves unrelated mappings and comments', () async {
    final file = File(p.join(temp.path, 'pubspec_overrides.yaml'));
    const text =
        '# keep header\nresolution: workspace\ndependency_overrides:\n'
        '  # keep other\n  other: ^1.0.0\n  squadron:\n    path: old\n';
    await file.writeAsString(text);
    await setManagedPubOverride(
      overrides: file,
      package: 'squadron',
      relativePath: 'new',
      previousManagedPaths: {'old'},
    );
    final updated = await file.readAsString();
    expect(updated, contains('# keep header'));
    expect(updated, contains('# keep other\n  other: ^1.0.0'));
    expect(updated, contains('resolution: workspace'));
    expect(updated, contains('path: new'));
    await setManagedPubOverride(
      overrides: file,
      package: 'squadron',
      relativePath: 'new',
      previousManagedPaths: {},
    );
    expect(await file.readAsString(), updated);
  });

  test('absent override is inserted', () async {
    final file = File(p.join(temp.path, 'pubspec_overrides.yaml'));
    await setManagedPubOverride(
      overrides: file,
      package: 'squadron',
      relativePath: 'new',
      previousManagedPaths: {},
    );
    expect(await file.readAsString(), contains('path: new'));
  });

  test('custom, incompatible and malformed overrides remain byte identical', () async {
    final file = File(p.join(temp.path, 'pubspec_overrides.yaml'));
    for (final text in [
      'dependency_overrides:\n  squadron:\n    path: custom\n',
      'dependency_overrides:\n  squadron:\n    git: https://example.invalid/repo\n',
      'dependency_overrides:\n  squadron: ^7.4.0\n',
      'dependency_overrides:\n  squadron:\n    hosted: https://example.invalid\n',
      'dependency_overrides:\n  squadron:\n    path: old\n    git: repo\n',
      'dependency_overrides:\n  squadron: 1\n  squadron: 2\n',
      'dependency_overrides:\n  squadron:\n    path: old\n    path: other\n',
      'dependency_overrides: []\n',
      'null\n',
      '[bad\n',
    ]) {
      await file.writeAsString(text);
      await expectLater(
        setManagedPubOverride(
          overrides: file,
          package: 'squadron',
          relativePath: 'new',
          previousManagedPaths: {'old'},
        ),
        throwsStateError,
      );
      expect(await file.readAsString(), text);
    }
  });
}
