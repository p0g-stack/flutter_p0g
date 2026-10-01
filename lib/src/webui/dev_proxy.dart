import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import 'flutter_webui.dart';

/// The dev server a WebUI page loads the app from (flutter-webui's
/// `dev.html`, `?dev=` or its `webui-dev-server` meta). It sits in front of
/// flutter_tools' `web-server` device, as the manager's page needs:
///
/// - CORS: the page stays on the manager's origin and fetches from here.
/// - flutter-webui's page glue (`flutter_webui.js`/`.css`) and its
///   `flutter_bootstrap.js`, filled with the build config the device serves,
///   in place of the app's stock `web/` files, as `build webui` does.
/// - everything else, WebSockets included, passed through to the device, so
///   hot restart and the debug service work unchanged.
class WebUiDevProxy {
  WebUiDevProxy._(this._server, this.upstream, this._bootstrap, this._flutterJs, this._fonts);

  final io.HttpServer _server;
  final Uri upstream;
  final Directory _bootstrap;
  final File _flutterJs;
  final Directory _fonts;
  final _client = io.HttpClient()..autoUncompress = false;

  /// The URL the page's `?dev=` takes.
  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/');

  /// Serves on 127.0.0.1:[port] (0 picks one) in front of [upstream].
  static Future<WebUiDevProxy> start({
    required int port,
    required Uri upstream,
    required Directory bootstrap,
    required File flutterJs,
    required Directory fonts,
  }) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, port);
    final proxy = WebUiDevProxy._(server, upstream, bootstrap, flutterJs, fonts);
    server.listen((r) => unawaited(proxy._handle(r)));
    return proxy;
  }

  Future<void> close() async {
    _client.close(force: true);
    await _server.close(force: true);
  }

  Future<void> _handle(io.HttpRequest request) async {
    try {
      if (io.WebSocketTransformer.isUpgradeRequest(request)) return await _proxySocket(request);
      final response = request.response;
      addCorsHeaders(response.headers, request.headers.value('origin'));
      if (request.method == 'OPTIONS') {
        response.statusCode = io.HttpStatus.noContent;
        return await response.close();
      }
      switch (request.uri.path) {
        case '/flutter_webui.js' || '/flutter_webui.css':
          return await _serveFile(request, _bootstrap.childFile(request.uri.pathSegments.last));
        case '/flutter_bootstrap.js':
          return await _serveBootstrap(request);
        case '/reloaded_sources.json':
          return await _serveReloadedSources(request);
        case '/assets/FontManifest.json':
          return await _serveFontManifest(request);
        case '/assets/$kRobotoAsset':
          return await _serveFile(request, bundledRoboto());
      }
      if (request.uri.path.startsWith('/fonts/')) return await _serveFont(request);
      await _proxy(request);
    } on Object catch (e) {
      try {
        request.response
          ..statusCode = io.HttpStatus.badGateway
          ..write('flutter_p0g dev proxy: $e');
        await request.response.close();
      } on Object {
        // The client went away.
      }
    }
  }

  Future<void> _serveFile(io.HttpRequest request, File file) async {
    final response = request.response;
    if (!file.existsSync()) {
      response.statusCode = io.HttpStatus.notFound;
      return await response.close();
    }
    response.headers.contentType = contentTypeFor(file.basename);
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _serveBootstrap(io.HttpRequest request) async {
    final upstreamRequest = await _client.getUrl(upstream.resolve('flutter_bootstrap.js'));
    final upstreamResponse = await upstreamRequest.close();
    final stock = await utf8.decodeStream(upstreamResponse);
    final config = extractBuildConfig(stock);
    final body = config == null
        ? stock // Not a bootstrap this tool knows; serve it as is.
        : fillBootstrap(
            _bootstrap.childFile('flutter_bootstrap.js').readAsStringSync(),
            flutterJs: _flutterJs,
            buildConfig: config,
          );
    request.response
      ..headers.contentType = io.ContentType('text', 'javascript', charset: 'utf-8')
      ..write(body);
    await request.response.close();
  }

  /// The bootstrap's `fontFallbackBaseUrl` is `<dev server>/fonts/`: web_ui's
  /// fallback fonts, as the release module bundles them.
  Future<void> _serveFont(io.HttpRequest request) async {
    final rest = request.uri.pathSegments.skip(1).toList();
    if (rest.isEmpty || rest.any((s) => s == '..' || s.isEmpty)) {
      request.response.statusCode = io.HttpStatus.notFound;
      return await request.response.close();
    }
    await _serveFile(request, _fonts.childFile(globals.fs.path.joinAll(rest)));
  }

  /// `flutter run` doesn't bundle Roboto as `build web --no-web-resources-cdn`
  /// does; without it no text renders.
  Future<void> _serveFontManifest(io.HttpRequest request) async {
    final up = await _client.getUrl(upstream.resolve('assets/FontManifest.json'));
    up.headers.removeAll(io.HttpHeaders.acceptEncodingHeader);
    final back = await up.close();
    final body = await utf8.decodeStream(back);
    request.response
      ..statusCode = back.statusCode
      ..headers.contentType = io.ContentType.json
      ..write(back.statusCode == io.HttpStatus.ok ? withRoboto(body) : body);
    await request.response.close();
  }

  /// Hot reload's module list: its `src` paths are origin-relative, and the
  /// page's origin is the manager's.
  Future<void> _serveReloadedSources(io.HttpRequest request) async {
    final up = await _client.getUrl(upstream.resolve('reloaded_sources.json'));
    up.headers.removeAll(io.HttpHeaders.acceptEncodingHeader);
    final back = await up.close();
    final body = await utf8.decodeStream(back);
    request.response
      ..statusCode = back.statusCode
      ..headers.contentType = io.ContentType.json
      ..write(back.statusCode == io.HttpStatus.ok ? absolutizeSources(body, url) : body);
    await request.response.close();
  }

  Future<void> _proxy(io.HttpRequest request) async {
    final target = upstream.replace(path: request.uri.path, query: request.uri.query);
    final out = await _client.openUrl(request.method, target);
    out.followRedirects = false;
    // The Host header goes through unchanged: the debug client dials
    // ws://<Host>/, which must be this server (flutter-webui docs/dev.md).
    request.headers.forEach((name, values) {
      if (_hopByHop.contains(name)) return;
      for (final v in values) {
        out.headers.add(name, v);
      }
    });
    await out.addStream(request);
    final back = await out.close();
    final response = request.response..statusCode = back.statusCode;
    back.headers.forEach((name, values) {
      if (_hopByHop.contains(name) ||
          name.startsWith('access-control-') ||
          name == io.HttpHeaders.cacheControlHeader) {
        return;
      }
      for (final v in values) {
        response.headers.add(name, v);
      }
    });
    await response.addStream(back);
    await response.close();
  }

  Future<void> _proxySocket(io.HttpRequest request) async {
    final target = upstream.replace(scheme: 'ws', path: request.uri.path, query: request.uri.query);
    final up = await io.WebSocket.connect(target.toString());
    final down = await io.WebSocketTransformer.upgrade(request);
    up.listen(down.add, onDone: () => down.close(), onError: (_) => down.close());
    down.listen(up.add, onDone: () => up.close(), onError: (_) => up.close());
  }

  static const _hopByHop = {
    'connection',
    'keep-alive',
    'proxy-connection',
    'transfer-encoding',
    'upgrade',
    'te',
    'trailer',
  };
}

/// The Roboto `build web` bundles without a CDN.
File bundledRoboto() => globals.fs.file(
  globals.fs.path.join(
    Cache.flutterRoot!,
    'engine',
    'src',
    'flutter',
    'txt',
    'third_party',
    'fonts',
    'Roboto-Regular.ttf',
  ),
);

/// Where `build web --no-web-resources-cdn` puts Roboto, under `assets/`.
const kRobotoAsset = 'fonts/fallback/Roboto-Regular.ttf';

/// `FontManifest.json` with Roboto at [kRobotoAsset] if it lacks a Roboto.
String withRoboto(String json) {
  final manifest = jsonDecode(json) as List<Object?>;
  if (manifest.any((e) => e is Map && e['family'] == 'Roboto')) return json;
  return jsonEncode([
    ...manifest,
    {
      'family': 'Roboto',
      'fonts': [
        {'asset': kRobotoAsset},
      ],
    },
  ]);
}

/// Content types the page's loads need (`.wasm` for streaming compile, a JS
/// type for module scripts).
io.ContentType contentTypeFor(String name) => switch (name.split('.').last) {
  'js' || 'mjs' => io.ContentType('text', 'javascript', charset: 'utf-8'),
  'css' => io.ContentType('text', 'css', charset: 'utf-8'),
  'json' => io.ContentType.json,
  'wasm' => io.ContentType('application', 'wasm'),
  'ttf' => io.ContentType('font', 'ttf'),
  'otf' => io.ContentType('font', 'otf'),
  'woff2' => io.ContentType('font', 'woff2'),
  'woff' => io.ContentType('font', 'woff'),
  _ => io.ContentType.binary,
};

/// `reloaded_sources.json` with each `src` resolved against [devServer].
String absolutizeSources(String json, Uri devServer) {
  final sources = jsonDecode(json) as List<Object?>;
  return jsonEncode([
    for (final s in sources)
      if (s case {'src': final String src})
        {...s as Map<String, Object?>, 'src': devServer.resolve(src).toString()}
      else
        s,
  ]);
}

/// The manager's page runs on its own origin; the dev server must let it in.
/// Every request is anonymous, so no credentials; nothing may be cached
/// across a restart (flutter-webui `docs/dev.md`).
@visibleForTesting
void addCorsHeaders(io.HttpHeaders headers, String? origin) {
  headers
    ..set('access-control-allow-origin', origin ?? '*')
    ..set('access-control-allow-methods', 'GET, OPTIONS')
    ..set('access-control-allow-headers', '*')
    ..set('access-control-allow-private-network', 'true')
    ..set(io.HttpHeaders.cacheControlHeader, 'no-store')
    ..add('vary', 'origin');
}

/// flutter-webui's `dev.html` with the module id and dev server filled in:
/// the page `run` puts in the module's webroot.
String fillDevHtml(String html, {required String moduleId, required Uri devServer}) => html
    .replaceFirst(
      '<meta name="webui-module-id" content="">',
      '<meta name="webui-module-id" content="${htmlAttr(moduleId)}">',
    )
    .replaceFirst(
      '<meta name="webui-dev-server" content="">',
      '<meta name="webui-dev-server" content="${htmlAttr(devServer.toString())}">',
    );
