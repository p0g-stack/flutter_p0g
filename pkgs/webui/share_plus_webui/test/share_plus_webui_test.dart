// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:share_plus_webui/src/share_plus_webui_impl.dart';
import 'package:webui_app_plane/testing.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

class Stock extends SharePlatform {
  final List<ShareParams> calls = [];

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return const ShareResult('stock', ShareResultStatus.success);
  }
}

const launcher = '/data/adb/modules/demo/webui_app_plane/termux-api';

FakeRootChannel withApp({String shareOutput = ''}) => FakeRootChannel(
  handler: (run) {
    if (run.argv[0] == '/system/bin/pm') {
      return const FakeProcessResult(
        stdout: 'package:/system/product/app/WebuiTermuxApi/WebuiTermuxApi.apk',
      );
    }
    if (run.argv.length > 1 && run.argv[1] == launcher) {
      return FakeProcessResult(stdout: shareOutput);
    }
    return const FakeProcessResult();
  },
);

void main() {
  late Stock stock;
  setUp(() => stock = Stock());

  SharePlusWebUiImpl sharer(FakeRootChannel fake, [FakeBridge? bridge]) =>
      SharePlusWebUiImpl(stock: stock, plane: AppPlane(fake.root(bridge)));

  test('text goes to Share on stdin with the subject as title', () async {
    final fake = withApp();
    final result = await sharer(fake)
        .share(ShareParams(text: 'héllo', subject: 'Hi'));
    expect(result, ShareResult.unavailable);
    final call = fake.runs.last;
    expect(call.argv.sublist(1), [
      launcher,
      '--package',
      'com.webui.termux.api',
      'Share',
      '--es',
      'action',
      'send',
      '--es',
      'title',
      'Hi',
    ]);
    expect(call.stdinText, 'héllo');
    expect(stock.calls, isEmpty);
  });

  test('a URI is shared as text', () async {
    final fake = withApp();
    await sharer(fake).share(ShareParams(uri: Uri.parse('https://x.org/a')));
    expect(fake.runs.last.stdinText, 'https://x.org/a');
  });

  test('one file is copied into the app dir and shared by path', () async {
    final fake = withApp();
    await sharer(fake).share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png',
            path: 'pic.png',
          ),
        ],
      ),
    );
    final write = fake.runs[1];
    expect(write.argv.take(2), ['/system/bin/sh', '-c']);
    expect(write.shArgs, [
      '/data/data/com.webui.termux.api/files/demo',
      '/data/data/com.webui.termux.api/files/demo/pic.png',
    ]);
    expect(write.stdin, [1, 2, 3]);
    expect(fake.runs.last.argv.sublist(4), [
      'Share',
      '--es',
      'action',
      'send',
      '--es',
      'file',
      '/data/data/com.webui.termux.api/files/demo/pic.png',
      '--es',
      'content-type',
      'image/png',
    ]);
  });

  test('fileNameOverrides names the copy', () async {
    final fake = withApp();
    await sharer(fake).share(
      ShareParams(
        files: [XFile.fromData(Uint8List(1), path: 'x')],
        fileNameOverrides: ['report.pdf'],
      ),
    );
    expect(fake.runs[1].shArgs.last, endsWith('/report.pdf'));
  });

  test('more than one file is refused', () async {
    await expectLater(
      sharer(withApp()).share(
        ShareParams(
          files: [
            XFile.fromData(Uint8List(1), path: 'a'),
            XFile.fromData(Uint8List(1), path: 'b'),
          ],
        ),
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'webui-share-multiple-files',
        ),
      ),
    );
  });

  test("ShareAPI's error text becomes a PlatformException", () async {
    await expectLater(
      sharer(withApp(shareOutput: 'Error: Nothing to share\n'))
          .share(ShareParams(text: ' ')),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          'Error: Nothing to share',
        ),
      ),
    );
  });

  test('without the app it is stock web', () async {
    final fake = FakeRootChannel(
      handler: (_) => const FakeProcessResult(exitCode: 1),
    );
    final result = await sharer(fake).share(ShareParams(text: 't'));
    expect(result.raw, 'stock');
    expect(fake.runs.single.argv, [
      '/system/bin/pm',
      'path',
      'com.webui.termux.api',
    ]);
  });

  test('a browser tab is stock web without touching root', () async {
    final fake = withApp();
    await sharer(fake, FakeBridge.browser()).share(ShareParams(text: 't'));
    expect(stock.calls, hasLength(1));
    expect(fake.runs, isEmpty);
  });
}
