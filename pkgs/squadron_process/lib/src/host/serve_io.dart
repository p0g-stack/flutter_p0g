import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logger/web.dart';
import 'package:squadron/squadron.dart';

import '../check/check_io.dart' as check;
import '../connect/connect_io.dart';
import '../launcher.dart';
import 'place_host.dart';

/// Options of the CLI serve mode, parsed from the app's own arguments.
///
/// ```
/// <app> serve [--port N] [--session-file PATH] [--grace-ms N]
///             [--first-link-grace-ms N]
/// ```
///
/// The token is never taken from argv (other apps can read
/// `/proc/<pid>/cmdline`): it is read from `SQUADRON_PROCESS_TOKEN` if set,
/// otherwise generated, and published only through stdout and the session
/// file.
class ServeOptions {
  const ServeOptions({
    this.port = 0,
    this.sessionFile,
    this.token,
    this.grace = const Duration(seconds: 10),
    this.firstLinkGrace = const Duration(seconds: 30),
  });

  final int port;
  final String? sessionFile;
  final String? token;
  final Duration grace;
  final Duration firstLinkGrace;

  /// Parses the arguments after `serve`. Throws [FormatException] on unknown
  /// or malformed options.
  static ServeOptions parse(
    List<String> args, {
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    var o = ServeOptions(token: env['SQUADRON_PROCESS_TOKEN']);
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      final eq = a.indexOf('=');
      final name = eq < 0 ? a : a.substring(0, eq);
      String value() {
        if (eq >= 0) return a.substring(eq + 1);
        if (++i >= args.length) throw FormatException('$name needs a value');
        return args[i];
      }

      int intValue() {
        final v = value();
        return int.tryParse(v) ??
            (throw FormatException('$name expects a number, got $v'));
      }

      switch (name) {
        case '--port':
          o = o._with(port: intValue());
        case '--session-file':
          o = o._with(sessionFile: value());
        case '--grace-ms':
          o = o._with(grace: Duration(milliseconds: intValue()));
        case '--first-link-grace-ms':
          o = o._with(firstLinkGrace: Duration(milliseconds: intValue()));
        default:
          throw FormatException('unknown serve option $a');
      }
    }
    return o;
  }

  ServeOptions _with({
    int? port,
    String? sessionFile,
    Duration? grace,
    Duration? firstLinkGrace,
  }) => ServeOptions(
    port: port ?? this.port,
    sessionFile: sessionFile ?? this.sessionFile,
    token: token,
    grace: grace ?? this.grace,
    firstLinkGrace: firstLinkGrace ?? this.firstLinkGrace,
  );
}

/// A running serve mode: the loopback WebSocket server and its [PlaceHost].
class ServedPlace {
  ServedPlace._(this.endpoint, this.host, this._server, this._sessionFile);

  final ProcessEndpoint endpoint;
  final PlaceHost host;
  final HttpServer _server;
  final File? _sessionFile;

  /// Completes after the host stopped and the server and session file are
  /// gone.
  late final Future<void> done = host.done.then((_) => _cleanUp());

  Future<void> close() async {
    await host.shutdown('closed');
    await done;
  }

  Future<void> _cleanUp() async {
    await _server.close(force: true);
    try {
      final f = _sessionFile;
      // Only remove the file if it still describes us; a newer host may have
      // replaced it.
      if (f != null &&
          ProcessEndpoint.tryParse(await f.readAsString())?.token ==
              endpoint.token) {
        await f.delete();
      }
    } catch (_) {}
  }
}

/// Starts serve mode for [service] in this process, without exiting.
///
/// Binds 127.0.0.1 only, accepts WebSocket links on `/squadron`, publishes
/// the endpoint to [ServeOptions.sessionFile] (atomic rename) and returns.
/// Facts are checked by this process for every handshake, merged with
/// [extraFacts].
Future<ServedPlace> startServe(
  Invoker service, {
  ServeOptions options = const ServeOptions(),
  Map<String, Object?> extraFacts = const {},
  Logger? logger,
}) async {
  final token = options.token ?? _newToken();
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    options.port,
  );
  final endpoint = ProcessEndpoint(port: server.port, token: token, pid: pid);
  final host = PlaceHost(
    service: service,
    token: token,
    grace: options.grace,
    firstLinkGrace: options.firstLinkGrace,
    logger: logger,
    checkFacts: () async => (await check.checkFacts()).merge(extraFacts),
  );

  server.listen((request) async {
    if (request.uri.path != '/squadron' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      host.accept(IoWebSocketLink(await WebSocketTransformer.upgrade(request)));
    } catch (e) {
      logger?.w('WebSocket upgrade failed: $e');
    }
  });

  File? sessionFile;
  final path = options.sessionFile;
  if (path != null) {
    sessionFile = File(path);
    await sessionFile.parent.create(recursive: true);
    final tmp = File('$path.$pid.tmp');
    await tmp.writeAsString(endpoint.encode(), flush: true);
    await tmp.rename(path);
  }

  return ServedPlace._(endpoint, host, server, sessionFile);
}

/// The CLI serve mode: hosts [service] until the lifetime rule stops it,
/// then stops the service and returns the exit code (0).
///
/// Prints the ready line (the endpoint as JSON) as the first line on stdout;
/// launchers read it. Logs go to stderr.
///
/// ```dart
/// // cli/bin/app.dart
/// Future<void> main(List<String> args) async {
///   if (args.firstOrNull == 'serve') {
///     exit(await serve(MyServiceWorker(), args.skip(1).toList()));
///   }
///   ...
/// }
/// ```
Future<int> serve(
  Invoker service,
  List<String> args, {
  Map<String, Object?> extraFacts = const {},
  Logger? logger,
}) async {
  final ServeOptions options;
  try {
    options = ServeOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('serve: ${e.message}');
    return 64; // EX_USAGE
  }
  final served = await startServe(
    service,
    options: options,
    extraFacts: extraFacts,
    logger: logger,
  );
  stdout.writeln(served.endpoint.encode());
  await stdout.flush();

  // A signal is a close, not a crash: cancel tasks the same way.
  final signals = [
    ProcessSignal.sigterm.watch(),
    ProcessSignal.sigint.watch(),
  ].map((s) => s.listen((sig) => served.host.shutdown('$sig'))).toList();

  await served.done;
  for (final s in signals) {
    await s.cancel();
  }
  if (service is Worker) service.stop();
  return 0;
}

String _newToken() {
  final r = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => r.nextInt(256)))
      .replaceAll('=', '');
}
