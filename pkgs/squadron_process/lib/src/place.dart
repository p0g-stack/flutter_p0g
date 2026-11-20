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
  ///
  /// [service] names the service on a host that serves several; places that
  /// run one service per worker ignore it.
  W bind<W extends Worker>(W worker, {String? service});
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
  W bind<W extends Worker>(W worker, {String? service}) {
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
    this.clientId,
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

  /// Who this client is to the host; defaults to [processClientId]. Links
  /// with one id get a service's log records once between them.
  final String? clientId;
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
    final channel = await open(
      ExceptionManager(),
      logger,
      service: _anyService,
    );
    await channel.close();
    return channel.facts;
  }

  // Facts are per host, so any service the host serves will do; null means
  // "the only one", and a host with several answers with their names.
  String? _anyService;

  @override
  W bind<W extends Worker>(W worker, {String? service}) {
    _anyService ??= service;
    worker.channelFactory = channelFactory(service: service);
    return worker;
  }

  /// The Squadron channel factory for [service] at this place.
  ChannelFactory channelFactory({String? service}) =>
      (exceptionManager, logger, entryPoint, startArguments) =>
          open(exceptionManager, logger, service: service);

  /// Opens one channel to [service] on the host, finding or starting the host
  /// first. If its link drops, the channel's next call opens a new one the
  /// same way, starting a new host if the old one is gone.
  Future<ProcessChannel> open(
    ExceptionManager exceptionManager,
    Logger? logger, {
    String? service,
  }) async => ProcessChannel.fromHandshake(
    await _link(service),
    exceptionManager: exceptionManager,
    logger: logger,
    reconnect: () => _link(service),
  );

  /// A handshaken link to [service], finding or starting the host first.
  Future<ProcessHandshake> _link(String? service) async {
    final endpoint = await _find();
    try {
      return await _handshake(endpoint, service);
    } on WorkerException catch (e) {
      // The host is there but does not serve that name: starting another
      // copy of the same CLI would not help.
      if (e.message.contains('service')) rethrow;
      return _retry(endpoint, e, service);
    } catch (e) {
      return _retry(endpoint, e, service);
    }
  }

  Future<ProcessHandshake> _retry(
    ProcessEndpoint endpoint,
    Object e,
    String? service,
  ) async {
    // The host we knew is gone (exited after its grace window, crashed, or a
    // stale session file). Find it again once: this starts a new one. Links
    // that fail together share that one new host: only the first to notice
    // forgets the old endpoint, and the others join its search.
    if (_same(_endpoint, endpoint)) {
      logger?.i('Place host at $endpoint unavailable ($e); finding again');
      _endpoint = null;
    }
    var next = await _find(skipStore: true);
    if (_same(next, endpoint)) {
      // We joined a search that read the same stale entry from the store.
      _endpoint = null;
      next = await _find(skipStore: true);
    }
    return _handshake(next, service);
  }

  static bool _same(ProcessEndpoint? a, ProcessEndpoint b) =>
      a != null && a.host == b.host && a.port == b.port && a.token == b.token;

  Future<ProcessHandshake> _handshake(
    ProcessEndpoint endpoint,
    String? service,
  ) async {
    final handshake = await ProcessHandshake.run(
      await _connect(endpoint),
      token: endpoint.token,
      service: service,
      clientId: clientId,
      timeout: handshakeTimeout,
    );
    _facts = handshake.facts;
    return handshake;
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
