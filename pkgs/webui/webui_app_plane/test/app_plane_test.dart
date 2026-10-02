// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:io';

import 'package:test/test.dart';
import 'package:webui_app_plane/testing.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

void main() {
  group('WebUiRoot', () {
    test('runs a process with stdin and collects its output', () async {
      final fake = FakeRootChannel(
        handler: (run) => FakeProcessResult(
          exitCode: 3,
          stdout: 'got ${run.stdinText}',
          stderr: 'warn',
        ),
      );
      final r = await fake.root().run(['/system/bin/cat'], stdin: [104, 105]);
      expect(r.exitCode, 3);
      expect(r.text, 'got hi');
      expect(r.errorText, 'warn');
      expect(fake.runs.single.argv, ['/system/bin/cat']);
    });

    test('sh passes values as arguments, never in the script', () async {
      final fake = FakeRootChannel();
      await fake.root().sh(r'echo "$1"', args: [r"it's $(x)"]);
      expect(fake.runs.single.argv, [
        '/system/bin/sh',
        '-c',
        r'echo "$1"',
        'sh',
        r"it's $(x)",
      ]);
    });

    test('writeFile writes page bytes as root, whole or not at all', () async {
      final fake = FakeRootChannel();
      await fake.root().writeFile('/storage/emulated/0/Download/a.txt', [104]);
      final run = fake.runs.single;
      expect(run.shArgs, ['/storage/emulated/0/Download/a.txt']);
      expect(run.stdin, [104]);
      final tmp = await Directory.systemTemp.createTemp('save');
      addTearDown(() => tmp.delete(recursive: true));
      final target = '${tmp.path}/new dir/a.txt';
      final p = await Process.start('sh', ['-c', run.argv[2], 'sh', target]);
      p.stdin.add('saved'.codeUnits);
      await p.stdin.close();
      expect(await p.exitCode, 0);
      expect(File(target).readAsStringSync(), 'saved');
      expect(File('$target.part').existsSync(), isFalse);
    }, testOn: 'linux');

    test('a failed writeFile throws', () async {
      final fake = FakeRootChannel(
        handler: (_) =>
            const FakeProcessResult(exitCode: 1, stderr: 'Read-only'),
      );
      await expectLater(
        fake.root().writeFile('/system/x', [1]),
        throwsA(
          isA<RootChannelException>().having(
            (e) => e.code,
            'code',
            'write-failed',
          ),
        ),
      );
    });

    test('a browser tab has no root', () {
      final fake = FakeRootChannel();
      final root = fake.root(FakeBridge.browser());
      expect(root.available, isFalse);
      expect(root.moduleDir, isNull);
    });

    test('APatch finds the module through the meta tag', () {
      final root = FakeRootChannel().root(FakeBridge.apatch());
      expect(root.available, isTrue);
      expect(root.moduleDir, '/data/adb/modules/demo');
    });
  });

  group('AppPlane', () {
    test(
      'pre-checks with pm path and grants the appop once, then calls',
      () async {
        final fake = FakeRootChannel(
          handler: (run) => run.argv.contains('path')
              ? const FakeProcessResult(
                  stdout:
                      'package:/data/app/~~x/com.webui.api.demo-y/base.apk\n',
                )
              : FakeProcessResult(stdout: 'echo:${run.stdinText}'),
        );
        final plane = AppPlane(fake.root());
        final r = await plane.call(
          'Share',
          extras: ['--es', 'action', 'send'],
          input: 'hello'.codeUnits,
        );
        await plane.call('Toast', input: 'x'.codeUnits);
        expect(r.text, 'echo:hello');
        expect(fake.runs.map((r) => r.argv).toList(), [
          ['/system/bin/pm', 'path', 'com.webui.api.demo'],
          [
            '/system/bin/appops',
            'set',
            'com.webui.api.demo',
            'SYSTEM_ALERT_WINDOW',
            'allow',
          ],
          [
            '/system/bin/sh',
            '/data/adb/modules/demo/webui_app_plane/termux-api',
            '--package',
            'com.webui.api.demo',
            'Share',
            '--es',
            'action',
            'send',
          ],
          [
            '/system/bin/sh',
            '/data/adb/modules/demo/webui_app_plane/termux-api',
            '--package',
            'com.webui.api.demo',
            'Toast',
          ],
        ]);
      },
    );

    test('a missing app is not-installed and is never called', () async {
      final fake = FakeRootChannel(
        handler: (run) => const FakeProcessResult(exitCode: 1),
      );
      final plane = AppPlane(fake.root());
      expect(await plane.isAvailable(), isFalse);
      await expectLater(
        plane.call('Share'),
        throwsA(
          isA<AppPlaneException>().having(
            (e) => e.code,
            'code',
            'not-installed',
          ),
        ),
      );
      expect(fake.runs, hasLength(1));
    });

    test('no root channel is unavailable', () async {
      final plane = AppPlane(FakeRootChannel().root(FakeBridge.browser()));
      expect(await plane.isAvailable(), isFalse);
      await expectLater(
        plane.call('Share'),
        throwsA(
          isA<AppPlaneException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });

    test('a failed call reports stderr', () async {
      final fake = FakeRootChannel(
        handler: (run) => run.argv.contains('path')
            ? const FakeProcessResult(stdout: 'package:/x.apk')
            : const FakeProcessResult(exitCode: 1, stderr: 'did not answer'),
      );
      await expectLater(
        AppPlane(fake.root()).call('Share'),
        throwsA(
          isA<AppPlaneException>()
              .having((e) => e.code, 'code', 'failed')
              .having((e) => e.message, 'message', contains('did not answer')),
        ),
      );
    });

    test('each hand-off gets its own folder in the app cache', () async {
      AppPlane.resetSweepsForTesting();
      final fake = FakeRootChannel();
      final plane = AppPlane(fake.root());
      final a = await plane.handoff();
      final b = await plane.handoff();
      // A second plugin's plane on the same page does not sweep again.
      await AppPlane(fake.root()).handoff();
      expect(a.dir, startsWith('/data/data/com.webui.api.demo/cache/handoff/'));
      expect(a.dir, isNot(b.dir));
      // The first hand-off sweeps old folders earlier pages left, once.
      expect(fake.runs, hasLength(1));
      expect(fake.runs.single.argv[2], contains('-mmin +'));
      expect(fake.runs.single.shArgs, [
        '/data/data/com.webui.api.demo/cache/handoff',
        '60',
      ]);
      final path = await a.write('a/b.png', [1, 2]);
      expect(path, '${a.dir}/a_b.png');
      expect(fake.runs.last.shArgs, [a.dir, path]);
      expect(fake.runs.last.stdin, [1, 2]);
      expect(a.path('.x'), '${a.dir}/file.x');
      await a.delete();
      expect(fake.runs.last.argv, ['/system/bin/rm', '-rf', a.dir]);
    });

    test('the hand-off write script works in a real sh', () async {
      final fake = FakeRootChannel();
      final plane = AppPlane(fake.root());
      final h = await plane.handoff();
      await h.write('x.txt', [1]);
      final script = fake.runs.last.argv[2];
      final tmp = await Directory.systemTemp.createTemp('handoff');
      addTearDown(() => tmp.delete(recursive: true));
      final app = Directory('${tmp.path}/data/data/pkg')
        ..createSync(recursive: true);
      Directory('${app.path}/cache').createSync();
      final other = '${app.path}/cache/handoff/other';
      File('$other/keep')
        ..createSync(recursive: true)
        ..writeAsStringSync('another call');
      final dir = '${app.path}/cache/handoff/call1';
      final p = await Process.start('sh', [
        '-c',
        script,
        'sh',
        dir,
        '$dir/new.txt',
      ]);
      p.stdin.add('fresh'.codeUnits);
      await p.stdin.close();
      expect(await p.exitCode, 0);
      expect(File('$other/keep').readAsStringSync(), 'another call');
      expect(File('$dir/new.txt').readAsStringSync(), 'fresh');
    }, testOn: 'linux');

    test('the sweep keeps young hand-offs and removes old ones', () async {
      AppPlane.resetSweepsForTesting();
      final fake = FakeRootChannel();
      await AppPlane(fake.root()).handoff();
      final tmp = await Directory.systemTemp.createTemp('sweep');
      addTearDown(() => tmp.delete(recursive: true));
      final young = Directory('${tmp.path}/young')..createSync();
      File('${young.path}/f').createSync();
      final old = Directory('${tmp.path}/old')..createSync();
      final touch = await Process.run('touch', ['-d', '2 hours ago', old.path]);
      expect(touch.exitCode, 0);
      final r = await Process.run('sh', [
        '-c',
        fake.runs.single.argv[2],
        'sh',
        tmp.path,
        '60',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(young.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      // A missing root is fine.
      final none = await Process.run('sh', [
        '-c',
        fake.runs.single.argv[2],
        'sh',
        '${tmp.path}/none',
        '60',
      ]);
      expect(none.exitCode, 0);
    }, testOn: 'linux');

    test('copyFrom copies a root path in without the page', () async {
      final fake = FakeRootChannel();
      final h = await AppPlane(fake.root()).handoff();
      final path = await h.copyFrom('/data/adb/demo/tmp/a.png', 'a.png');
      expect(path, '${h.dir}/a.png');
      expect(fake.runs.last.stdin, isEmpty);
      final tmp = await Directory.systemTemp.createTemp('copy');
      addTearDown(() => tmp.delete(recursive: true));
      final src = File('${tmp.path}/src.bin')..writeAsStringSync('bytes');
      final dir = '${tmp.path}/data/data/pkg/cache/handoff/call1';
      Directory('${tmp.path}/data/data/pkg/cache').createSync(recursive: true);
      final args = [...fake.runs.last.shArgs];
      // The host has no /system/bin/sh.
      final script = fake.runs.last.argv[2].replaceAll('/system/bin/sh', 'sh');
      final r = await Process.run('sh', [
        '-c',
        script,
        'sh',
        src.path,
        args[1],
        dir,
        '$dir/a.png',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('$dir/a.png').readAsStringSync(), 'bytes');
      final missing = await Process.run('sh', [
        '-c',
        script,
        'sh',
        '${tmp.path}/nope',
        args[1],
        dir,
        '$dir/b.png',
      ]);
      expect(missing.exitCode, isNot(0));
    }, testOn: 'linux');
  });

  test('the package is derived from the module id', () {
    expect(appPlanePackage('demo'), 'com.webui.api.demo');
    expect(appPlanePackage('my-mod.x'), 'com.webui.api.my_mod_x');
    expect(appPlanePackage('2fa'), 'com.webui.api.m2fa');
    expect(AppPlane(FakeRootChannel().root()).package, 'com.webui.api.demo');
    expect(AppPlane(FakeRootChannel().root(), package: 'x.y').package, 'x.y');
  });

  group('scanMedia', () {
    test('broadcasts one scan per file as root, app or not', () async {
      final fake = FakeRootChannel(
        handler: (run) => run.argv.contains('path')
            ? const FakeProcessResult(exitCode: 1)
            : const FakeProcessResult(stdout: 'Broadcast completed: result=0'),
      );
      await AppPlane(fake.root())
          .scanMedia(['/storage/emulated/0/Download/my file.png']);
      expect(fake.runs.last.argv, [
        '/system/bin/am',
        'broadcast',
        '--user',
        'current',
        '-a',
        'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d',
        'file:///storage/emulated/0/Download/my%20file.png',
      ]);
    });

    test('needs the root channel', () async {
      final fake = FakeRootChannel();
      await expectLater(
        AppPlane(fake.root(FakeBridge.browser())).scanMedia(['/x']),
        throwsA(
          isA<AppPlaneException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      await AppPlane(fake.root()).scanMedia([]);
      expect(fake.runs, isEmpty);
    });
  });
}
