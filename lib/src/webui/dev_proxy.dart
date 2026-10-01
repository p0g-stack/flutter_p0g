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
  WebUiDevProxy._(this._server, this.upstream, this._bootstrap, this._flutterJs);

  final io.HttpServer _server;
  final Uri upstream;
  final Directory _bootstrap;
  final File _flutterJs;
  final _client = io.HttpClient()..autoUncompress = false;
  final _fonts = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = io.HttpClient.findProxyFromEnvironment;

  /// The URL the page's `?dev=` takes.
  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/');

  /// Serves on 127.0.0.1:[port] (0 picks one) in front of [upstream].
  static Future<WebUiDevProxy> start({
    required int port,
    required Uri upstream,
    required Directory bootstrap,
    required File flutterJs,
  }) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, port);
    final proxy = WebUiDevProxy._(server, upstream, bootstrap, flutterJs);
    server.listen((r) => unawaited(proxy._handle(r)));
    return proxy;
  }

  Future<void> close() async {
    _client.close(force: true);
    _fonts.close(force: true);
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
    final response = request.response
      ..headers.contentType = file.basename.endsWith('.css')
          ? io.ContentType('text', 'css', charset: 'utf-8')
          : io.ContentType('text', 'javascript', charset: 'utf-8')
      ..headers.set(io.HttpHeaders.cacheControlHeader, 'no-cache');
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
            buildConfig: config + kDevLoaderConfig,
          );
    request.response
      ..headers.contentType = io.ContentType('text', 'javascript', charset: 'utf-8')
      ..headers.set(io.HttpHeaders.cacheControlHeader, 'no-cache')
      ..write(body);
    await request.response.close();
  }

  /// The bootstrap's `fontFallbackBaseUrl` is `fonts/` (release builds
  /// bundle Roboto). In dev the page reaches only this server, so fonts come
  /// from Google Fonts through the host, or Roboto from the engine's copy
  /// when the host is offline; anything else is a 404 the engine skips.
  Future<void> _serveFont(io.HttpRequest request) async {
    final rest = request.uri.path.substring('/fonts/'.length);
    final response = request.response;
    try {
      final up = await _fonts.getUrl(Uri.parse('https://fonts.gstatic.com/s/$rest'));
      final back = await up.close().timeout(const Duration(seconds: 5));
      if (back.statusCode == io.HttpStatus.ok) {
        response.headers.contentType = io.ContentType('font', 'woff2');
        await response.addStream(back);
        return await response.close();
      }
      await back.drain<void>();
    } on Object {
      // Offline host.
    }
    final roboto = bundledRoboto();
    if (rest.startsWith('roboto/') && roboto.existsSync()) {
      response.headers.contentType = io.ContentType('font', 'ttf');
      await response.addStream(roboto.openRead());
    } else {
      response.statusCode = io.HttpStatus.notFound;
    }
    await response.close();
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
      ..headers.set(io.HttpHeaders.cacheControlHeader, 'no-cache')
      ..write(back.statusCode == io.HttpStatus.ok ? absolutizeSources(body, url) : body);
    await request.response.close();
  }

  Future<void> _proxy(io.HttpRequest request) async {
    final target = upstream.replace(path: request.uri.path, query: request.uri.query);
    final out = await _client.openUrl(request.method, target);
    out.followRedirects = false;
    final rewrite = _isEntryScript(request.uri.path);
    request.headers.forEach((name, values) {
      if (_hopByHop.contains(name) || (rewrite && name == 'accept-encoding')) return;
      for (final v in values) {
        out.headers.add(name, name == 'host' ? '${upstream.host}:${upstream.port}' : v);
      }
    });
    await out.addStream(request);
    final back = await out.close();
    final response = request.response..statusCode = back.statusCode;
    back.headers.forEach((name, values) {
      if (_hopByHop.contains(name) || name.startsWith('access-control-')) return;
      for (final v in values) {
        response.headers.add(name, v);
      }
    });
    if (rewrite && back.statusCode == io.HttpStatus.ok) {
      // The debug service's client (injected into the entry's bootstrap
      // script) resolves this against the page, the manager's origin here.
      final js = absolutizeReloadedSources(await utf8.decodeStream(back), url);
      response.headers
        ..removeAll(io.HttpHeaders.contentLengthHeader)
        ..removeAll(io.HttpHeaders.contentEncodingHeader)
        ..chunkedTransferEncoding = true;
      response.write(js);
      return await response.close();
    }
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

  /// Top-level scripts: `main.dart.js` and the `*.bootstrap.js` the debug
  /// service injects its client into.
  static bool _isEntryScript(String path) =>
      RegExp(r'^/(main\.dart|[^/]+\.bootstrap)\.js$').hasMatch(path);

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

/// Points DWDS's `\$reloadedSourcesPath` (relative, so resolved against the
/// page) at the dev server.
String absolutizeReloadedSources(String js, Uri devServer) => js.replaceAllMapped(
  RegExp(r'(\$reloadedSourcesPath\s*=\s*")([^":]+)(")'),
  (m) => '${m[1]}${devServer.resolve(m[2]!)}${m[3]}',
);

/// Runs after flutter.js and the build config, before the bootstrap's
/// `load()`: the page stays on the manager's origin and the app comes from
/// the dev server (`window.flutterWebUiDevServer`, set by `dev.html`), so the
/// loader's relative URLs are based there.
const kDevLoaderConfig = r'''
(function () {
  var dev = window.flutterWebUiDevServer;
  if (!dev) return;
  var loader = _flutter.loader;
  var load = loader.load.bind(loader);
  loader.load = function (options) {
    options = options || {};
    options.config = Object.assign(
      {entrypointBaseUrl: dev, assetBase: dev, canvasKitBaseUrl: dev + 'canvaskit/'},
      options.config || {},
      {fontFallbackBaseUrl: dev + 'fonts/'});
    return load(options);
  };
})();
''';

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
@visibleForTesting
void addCorsHeaders(io.HttpHeaders headers, String? origin) {
  headers
    ..set('access-control-allow-origin', origin ?? '*')
    ..set('access-control-allow-methods', 'GET, POST, PUT, OPTIONS')
    ..set('access-control-allow-headers', '*')
    ..set('access-control-allow-private-network', 'true');
  if (origin != null) {
    headers
      ..set('access-control-allow-credentials', 'true')
      ..add('vary', 'origin');
  }
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
