import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_p0g/src/webui/flutter_webui.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('web SDK integrity and fetch failures propagate without replacing the old SDK', () async {
    final fs = MemoryFileSystem.test();
    final oldRoot = Cache.flutterRoot;
    Cache.flutterRoot = '/flutter';
    try {
      await context.run<void>(
        overrides: {FileSystem: () => fs, Logger: () => BufferLogger.test()},
        body: () async {
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

  test('the released web SDK is used only for its web_ui tree and engine', () {
    expect(releasedWebSdkFits(tree: kWebSdkTree, engine: kWebSdkEngine), isTrue);
    expect(releasedWebSdkFits(tree: 'other', engine: kWebSdkEngine), isFalse);
    expect(releasedWebSdkFits(tree: kWebSdkTree, engine: 'other'), isFalse);
    expect(kWebSdkUrl, endsWith('/releases/download/$kWebSdkRelease/flutter-webui-web-sdk.tar.xz'));
  });
}
