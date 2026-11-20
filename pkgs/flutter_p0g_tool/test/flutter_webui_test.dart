import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/file_system.dart' show FileSystem;
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_p0g_tool/src/webui/flutter_webui.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'lock_fixture.dart';

void main() {
  test('web SDK integrity and fetch failures propagate without replacing the old SDK', () async {
    final fs = MemoryFileSystem.test();
    final oldRoot = Cache.flutterRoot;
    Cache.flutterRoot = '/flutter';
    try {
      await context.run<void>(
        overrides: {FileSystem: () => fs, Logger: () => BufferLogger.test()},
        body: () async {
          await installCommittedLock();
          final marker = patchedWebSdk().childFile('verified-old-sdk')
            ..createSync(recursive: true)
            ..writeAsStringSync('old');
          await expectLater(
            installReleasedWebSdk(fetch: (_) async => [1, 2, 3]),
            throwsA(
              isA<ToolExit>().having((error) => error.message, 'message', contains('sha256')),
            ),
          );
          await expectLater(
            installReleasedWebSdk(fetch: (_) async => throwToolExit('HTTP 503')),
            throwsA(isA<ToolExit>().having((error) => error.message, 'message', 'HTTP 503')),
          );
          expect(marker.readAsStringSync(), 'old');
        },
      );
    } finally {
      Cache.flutterRoot = oldRoot;
    }
  });

  test('extracts the build config block flutter_tools writes', () {
    const block =
        'if (!window._flutter) {\n  window._flutter = {};\n}\n'
        '_flutter.buildConfig = {"engineRevision":"x","builds":[]};\n';
    const built = '/* flutter.js */\n$block\n_flutter.loader.load();\n';
    expect(extractBuildConfig(built), block);
    expect(extractBuildConfig('_flutter.loader.load();'), isNull);
  });

  test('fills module id and title, escaped', () {
    const html = '<meta name="webui-module-id" content="">\n<title>Flutter</title>';
    final out = fillIndexHtml(html, moduleId: 'demo', title: 'A & <B>');
    expect(out, contains('<meta name="webui-module-id" content="demo">'));
    expect(out, contains('<title>A &amp; &lt;B></title>'));
  });

  test('the release page uses the bootstrap without dev.html', () {
    expect(kBootstrapFiles, isNot(contains('dev.html')));
    expect(kBootstrapFiles, containsAll(['index.html', 'flutter_bootstrap.js']));
  });

  test('web SDK paths move under the patched SDK, others stay', () {
    final ctx = p.Context(style: p.Style.posix);
    expect(
      rebaseWebSdkPath(
        ctx,
        '/f/cache/flutter_web_sdk/kernel/x.dill',
        '/f/cache/flutter_web_sdk',
        '/p/sdk',
      ),
      '/p/sdk/kernel/x.dill',
    );
    expect(
      rebaseWebSdkPath(ctx, '/f/cache/artifacts/x', '/f/cache/flutter_web_sdk', '/p/sdk'),
      '/f/cache/artifacts/x',
    );
  });

  test('the released web SDK is used only for its patch set and engine', () async {
    final repo = await realRepository();
    final patchSet = webSdkPatchSet(
      const LocalFileSystem().directory(repo.uri.resolve('web_sdk/patches').toFilePath()),
    );
    final fs = MemoryFileSystem.test();
    await context.run<void>(
      overrides: {FileSystem: () => fs},
      body: () async {
        final lock = await installCommittedLock();
        expect(lock.webSdk.field('patchSet'), patchSet);
        expect(await releasedWebSdkFits(patchSet: patchSet, engine: lock.engine), isTrue);
        expect(await releasedWebSdkFits(patchSet: 'other', engine: lock.engine), isFalse);
        expect(await releasedWebSdkFits(patchSet: patchSet, engine: 'other'), isFalse);
      },
    );
  });

  test('the patch set ignores commit metadata and blob ids, not hunks', () {
    final fs = MemoryFileSystem.test();
    final patches = fs.directory('/patches')..createSync();
    String patch({String from = 'aaaa', String index = '1111..2222', String hunk = '+b'}) =>
        'From $from Mon Sep 17 00:00:00 2001\n'
        'Subject: [PATCH] change\n\n---\n'
        'diff --git a/x b/x\nindex $index 100644\n--- a/x\n+++ b/x\n'
        '@@ -1 +1 @@\n-a\n$hunk\n-- \n2.56.0\n\n';
    String digest(String text) {
      patches.childFile('0001-change.patch').writeAsStringSync(text);
      return webSdkPatchSet(patches);
    }

    final base = digest(patch());
    expect(digest(patch(from: '0' * 40, index: '3333..4444')), base);
    expect(digest(patch(hunk: '+c')), isNot(base));
  });
}
