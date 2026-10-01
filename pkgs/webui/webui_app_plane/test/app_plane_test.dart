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
                      'package:/system/product/app/WebuiTermuxApi/base.apk\n',
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

    test('writeAppFile writes into the app dir for the module', () async {
      final fake = FakeRootChannel();
      final path = await AppPlane(fake.root()).writeAppFile('a/b.png', [1, 2]);
      expect(path, '/data/data/com.webui.api.demo/files/demo/a_b.png');
      final run = fake.runs.single;
      expect(run.shArgs, ['/data/data/com.webui.api.demo/files/demo', path]);
      expect(run.stdin, [1, 2]);
    });

    test('the writeAppFile script works in a real sh', () async {
      final fake = FakeRootChannel();
      await AppPlane(fake.root()).writeAppFile('x.txt', [1]);
      final script = fake.runs.single.argv[2];
      final tmp = await Directory.systemTemp.createTemp('appfile');
      addTearDown(() => tmp.delete(recursive: true));
      final app = Directory('${tmp.path}/data/data/pkg')
        ..createSync(recursive: true);
      final dir = '${app.path}/files/demo';
      File('$dir/old')
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
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
      expect(File('$dir/old').existsSync(), isFalse);
      expect(File('$dir/new.txt').readAsStringSync(), 'fresh');
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
