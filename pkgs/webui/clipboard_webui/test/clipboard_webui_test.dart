// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:clipboard_webui/src/clipboard_webui_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webui/flutter_webui.dart';
import 'package:webui_app_plane/testing.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

class Browser implements TextClipboard {
  Browser({this.canRead = false, this.canWrite = true});

  final bool canRead;
  final bool canWrite;
  String? text;

  @override
  Future<String?> getText() async {
    if (!canRead) throw StateError('Clipboard read is not available.');
    return text;
  }

  @override
  Future<void> setText(String value) async {
    if (!canWrite) throw StateError('Clipboard write was refused.');
    text = value;
  }
}

const launcher = '/data/adb/modules/demo/webui_app_plane/termux-api';

FakeRootChannel withApp({bool installed = true, String clip = ''}) =>
    FakeRootChannel(
      handler: (run) {
        if (run.argv[0] == '/system/bin/pm') {
          return installed
              ? const FakeProcessResult(stdout: 'package:/x/base.apk')
              : const FakeProcessResult(exitCode: 1);
        }
        if (run.argv.length > 1 && run.argv[1] == launcher) {
          return FakeProcessResult(stdout: clip);
        }
        return const FakeProcessResult();
      },
    );

List<String>? appCall(FakeRootChannel fake) {
  for (final r in fake.runs.reversed) {
    if (r.argv.length > 1 && r.argv[1] == launcher) return r.argv.sublist(4);
  }
  return null;
}

void main() {
  AppPlaneClipboard clipboard(FakeRootChannel fake, TextClipboard? browser) =>
      AppPlaneClipboard(plane: AppPlane(fake.root()), browser: () => browser);

  test('reads come from the app when the WebView refuses', () async {
    final fake = withApp(clip: 'line 1\nline 2\n');
    final text = await clipboard(fake, Browser()).getText();
    expect(text, 'line 1\nline 2\n');
    final argv = fake.runs.lastWhere((r) => r.argv[1] == launcher).argv;
    expect(argv.sublist(2, 4), ['--package', 'com.webui.api.demo']);
    expect(argv.sublist(4), [
      '--wait',
      '30',
      'Clipboard',
      '--es',
      'api_version',
      '2',
    ]);
  });

  test('a browser that can read is used as is', () async {
    final fake = withApp(clip: 'app');
    final browser = Browser(canRead: true)..text = 'browser';
    expect(await clipboard(fake, browser).getText(), 'browser');
    expect(appCall(fake), isNull);
  });

  test('writes stay in the browser when it accepts them', () async {
    final fake = withApp();
    final browser = Browser();
    await clipboard(fake, browser).setText('hi');
    expect(browser.text, 'hi');
    expect(appCall(fake), isNull);
  });

  test('a refused write goes to the app on stdin', () async {
    final fake = withApp();
    await clipboard(fake, Browser(canWrite: false)).setText('héllo\n');
    final run = fake.runs.lastWhere((r) => r.argv[1] == launcher);
    expect(run.argv.sublist(4), [
      'Clipboard',
      '--es',
      'api_version',
      '2',
      '--ez',
      'set',
      'true',
    ]);
    expect(run.stdin, utf8.encode('héllo\n'));
  });

  test('without the app the browser error stands', () async {
    final fake = withApp(installed: false);
    await expectLater(
      clipboard(fake, Browser()).getText(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not available'),
        ),
      ),
    );
  });

  test('a failing app call is a StateError for the engine', () async {
    final fake = FakeRootChannel(
      handler: (run) => run.argv[0] == '/system/bin/pm'
          ? const FakeProcessResult(stdout: 'package:/x/base.apk')
          : run.argv.length > 1 && run.argv[1] == launcher
          ? const FakeProcessResult(exitCode: 1, stderr: 'timed out')
          : const FakeProcessResult(),
    );
    await expectLater(
      clipboard(fake, Browser()).getText(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });
}
