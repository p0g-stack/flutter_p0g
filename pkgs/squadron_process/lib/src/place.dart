import 'dart:async';
import 'dart:math';

import 'package:logger/web.dart';
import 'package:squadron/squadron.dart';

import 'connect/connect.dart';
import 'facts.dart';
import 'launcher.dart';
import 'link.dart';
import 'process_channel.dart';

/// Where a Squadron service runs.
///
/// The same service class runs in every place; only the channel differs.
/// [bind] points a worker at this place before it starts.
sealed class Place {
  const Place();

  /// `isolate`, `web_worker` or `process`.
  String get kind;

  /// What this place can do, as checked by the place itself.
  Future<PlaceFacts> facts();

  /// Points [worker] at this place and returns it. Call before the worker
  /// starts (before its first request).
  W bind<W extends Worker>(W worker);
}

/// Squadron's own place for this platform: an isolate on the Dart VM, a Web
/// Worker in a browser. [check] runs in the current context, which has the
/// same capabilities as the isolate or worker it spawns.
final class LocalPlace extends Place {
  const LocalPlace({this.check});

  final FactsCheck? check;

  @override
  String get kind =>
      Squadron.platformType.isWeb ? PlaceKind.webWorker : PlaceKind.isolate;

  @override
  Future<PlaceFacts> facts() async {
    final check = this.check;
    return check == null ? const PlaceFacts.none() : PlaceFacts(await check());
  }

  @override
  W bind<W extends Worker>(W worker) {
    worker.channelFactory = null;
    return worker;
  }
}

abstract final class PlaceKind {
  static const isolate = 'isolate';
  static const webWorker = 'web_worker';
  static const process = 'process';
}

/// Opens a [PlaceLink] to [endpoint]. The default is a WebSocket.
typedef LinkConnector = Future<PlaceLink> Function(ProcessEndpoint endpoint);

/// Another process (usually the app's own CLI in serve mode, often elevated),
/// reached over a loopback WebSocket.
///
/// Each worker bound here opens its own link. Before the first link,
/// [ProcessPlace] finds the host: first the [store] (a host that is already
/// running, e.g. after the client restarted), then the [launcher] with [command]
/// (reading the endpoint from the host's ready line).
final class ProcessPlace extends Place {
  ProcessPlace({
    this.launcher,
    this.command,
    this.store,
    ProcessEndpoint? endpoint,
    LinkConnector? connector,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.readyTimeout = const Duration(seconds: 120),
    this.storePollInterval = const Duration(milliseconds: 250),
    this.logger,
  }) : _endpoint = endpoint,
       _connect = connector ?? connectWebSocket,
       assert(
         endpoint != null || store != null || launcher != null,
         'ProcessPlace needs an endpoint, a store or a launcher',
       ),
       assert(
         launcher == null || command != null,
         'a launcher needs a command',
       );

  final ProcessLauncher? launcher;
  final ProcessCommand? command;
  final EndpointStore? store;
  final Duration handshakeTimeout;

  /// How long a launch may take, including a person answering an
  /// elevation prompt.
  final Duration readyTimeout;
  final Duration storePollInterval;
  final Logger? logger;
  final LinkConnector _connect;

  ProcessEndpoint? _endpoint;
  Future<ProcessEndpoint>? _finding;
  PlaceFacts? _facts;

  @override
  String get kind => PlaceKind.process;

  /// The endpoint in use, once found.
  ProcessEndpoint? get endpoint => _endpoint;

  /// The facts from the latest handshake. Opens (and closes) a link if no
  /// worker has connected yet.
  @override
  Future<PlaceFacts> facts() async {
    final known = _facts;
    if (known != null) return known;
    final channel = await open(ExceptionManager(), logger);
    await channel.close();
    return channel.facts;
  }

  @override
  W bind<W extends Worker>(W worker) {
    worker.channelFactory = channelFactory;
    return worker;
  }

  /// The Squadron channel factory for this place.
  ChannelFactory get channelFactory =>
      (exceptionManager, logger, entryPoint, startArguments) =>
          open(exceptionManager, logger);

  /// Opens one channel to the host, finding or starting the host first.
  Future<ProcessChannel> open(
    ExceptionManager exceptionManager,
    Logger? logger,
  ) async {
    var endpoint = await _find();
    try {
      return await _handshake(endpoint, exceptionManager, logger);
    } catch (e) {
      // The host we knew is gone (exited after its grace window, or a stale
      // session file). Find it again once: this starts a new one.
      this.logger?.i('Place host at $endpoint unavailable ($e); finding again');
      _endpoint = null;
      _finding = null;
      endpoint = await _find(skipStore: true);
      return _handshake(endpoint, exceptionManager, logger);
    }
  }

  Future<ProcessChannel> _handshake(
    ProcessEndpoint endpoint,
    ExceptionManager exceptionManager,
    Logger? logger,
  ) async {
    final link = await _connect(endpoint);
    final channel = await ProcessChannel.connect(
      link,
      token: endpoint.token,
      exceptionManager: exceptionManager,
      logger: logger,
      timeout: handshakeTimeout,
    );
    _facts = channel.facts;
    return channel;
  }

  Future<ProcessEndpoint> _find({bool skipStore = false}) {
    final known = _endpoint;
    if (known != null) return Future.value(known);
    return _finding ??= () async {
      try {
        ProcessEndpoint? found;
        if (!skipStore) found = await store?.read();
        found ??= await _launch();
        return _endpoint = found;
      } finally {
        _finding = null;
      }
    }();
  }

  Future<ProcessEndpoint> _launch() async {
    final launcher = this.launcher, base = this.command;
    if (launcher == null || base == null) {
      throw WorkerException('No place host is running and no launcher is set');
    }
    // A launch id ties the endpoint we read back to this launch: elevation
    // front-ends (pkexec, UAC, macOS admin prompts) often give no stdout, so
    // the host may only be found through the store, where an older host's
    // entry could still be lying around. It is not a secret.
    final launchId = newLaunchId();
    final command = base.withArguments([
      ...base.arguments,
      '--launch-id',
      launchId,
    ]);
    logger?.i('Starting place host: $command');
    final process = await launcher.launch(command);

    final ready = Completer<ProcessEndpoint>();
    void found(ProcessEndpoint? e) {
      if (e != null && e.launchId == launchId && !ready.isCompleted) {
        ready.complete(e);
      }
    }

    // stdout ready line, when the launcher can see stdout.
    final sub = process.stdoutLines.listen(
      (line) => found(ProcessEndpoint.tryParse(line)),
      onError: (_) {},
      cancelOnError: false,
    );
    // The store, for launchers that cannot.
    final store = this.store;
    final poll = store == null
        ? null
        : Timer.periodic(storePollInterval, (_) async {
            try {
              found(await store.read());
            } catch (_) {}
          });
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          WorkerException(
            'Place host exited with code $code before it was ready ($command)',
          ),
        );
      }
    }, onError: (_) {});

    try {
      return await ready.future.timeout(readyTimeout);
    } on TimeoutException {
      throw WorkerException(
        'Place host did not report ready within $readyTimeout ($command)',
      );
    } finally {
      poll?.cancel();
      await sub.cancel();
    }
  }
}

/// A random, non-secret id for one launch.
String newLaunchId() {
  final r = Random.secure();
  return List.generate(
    8,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
