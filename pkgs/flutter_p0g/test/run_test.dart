import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_p0g/src/commands/run.dart';
import 'package:flutter_p0g/src/webui/dev_proxy.dart';
import 'package:test/test.dart';

void main() {
  final dev = Uri.parse('http://127.0.0.1:8800/');

  test('dev.html gets the module id and dev server', () {
    const html =
        '<meta name="webui-module-id" content="">\n<meta name="webui-dev-server" content="">';
    final out = fillDevHtml(html, moduleId: 'counter', devServer: dev);
    expect(out, contains('<meta name="webui-module-id" content="counter">'));
    expect(out, contains('<meta name="webui-dev-server" content="http://127.0.0.1:8800/">'));
  });

  test('reloaded sources resolve against the dev server', () {
    final out = jsonDecode(
      absolutizeSources(
        jsonEncode([
          {'src': '/packages/counter/main.dart.lib.js', 'module': 'm', 'libraries': <String>[]},
        ]),
        dev,
      ),
    ) as List;
    expect((out.single as Map)['src'], 'http://127.0.0.1:8800/packages/counter/main.dart.lib.js');
    expect((out.single as Map)['module'], 'm');
  });

  test('the font manifest gets Roboto once', () {
    final out = jsonDecode(
      withRoboto(
        jsonEncode([
          {
            'family': 'MaterialIcons',
            'fonts': [
              {'asset': 'fonts/MaterialIcons-Regular.otf'},
            ],
          },
        ]),
      ),
    ) as List;
    expect(out.last, {
      'family': 'Roboto',
      'fonts': [
        {'asset': 'fonts/fallback/Roboto-Regular.ttf'},
      ],
    });
    final again = withRoboto(jsonEncode(out));
    expect((jsonDecode(again) as List), hasLength(2));
  });

  test('content types the page needs', () {
    expect(contentTypeFor('canvaskit.wasm').mimeType, 'application/wasm');
    expect(contentTypeFor('main.dart.mjs').mimeType, 'text/javascript');
    expect(contentTypeFor('Roboto.ttf').mimeType, 'font/ttf');
  });

  test('CORS echoes the origin', () async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      addCorsHeaders(r.response.headers, r.headers.value('origin'));
      r.response.close();
    });
    final client = io.HttpClient();
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
    req.headers.set('origin', 'https://mui.kernelsu.org');
    final res = await req.close();
    expect(res.headers.value('access-control-allow-origin'), 'https://mui.kernelsu.org');
    expect(res.headers.value('access-control-allow-private-network'), 'true');
    expect(res.headers.value('access-control-allow-credentials'), isNull);
    expect(res.headers.value('cache-control'), 'no-store');
    client.close();
    await server.close();
  });

  test('page swap keeps the release page once and restores it', () {
    final inScript = swapInScript('/data/adb/modules/counter/webroot', '/data/local/tmp/d.html');
    expect(
      inScript,
      "cd '/data/adb/modules/counter/webroot' && "
      '{ [ -f index.release.html ] || mv index.html index.release.html; } && '
      "cp '/data/local/tmp/d.html' index.html && chmod 0644 index.html && "
      "rm -f '/data/local/tmp/d.html'",
    );
    expect(
      swapOutScript('/data/adb/modules/counter/webroot'),
      "cd '/data/adb/modules/counter/webroot' && [ -f index.release.html ] && "
      'mv -f index.release.html index.html',
    );
  });
}
