import 'dart:async';
import 'dart:typed_data';

import 'package:cancelation_token/cancelation_token.dart';
import 'package:logger/web.dart';
import 'package:squadron/squadron.dart';

import '../facts.dart';
import '../link.dart';
import '../place.dart';
import '../protocol.dart';

/// Serves Squadron services to process-place clients.
///
/// [services] maps a name to the service's invoker, usually the generated
/// worker (an isolate inside this process) or a `LocalWorker`. Each link names
/// one service in its hello; a link that names none gets the only service when
/// there is exactly one.
/// Nothing Squadron does is redone here: cancellation, streaming and
/// exceptions are Squadron's, forwarded over the link.
///
/// Lifetime: the host keeps running while at least one link is open, and for
/// [grace] after the last one closes (a client that restarts, say a
/// reloaded web page, reconnects within it). Work keeps running through that window; results for a link
/// that went away are dropped. If no link returns in time, every running
/// task is cancelled and [done] completes. A host nobody connects to at all
/// gives up after [firstLinkGrace].
class PlaceHost {
  PlaceHost({
    required this.services,
    required this.token,
    Future<PlaceFacts> Function()? checkFacts,
    this.grace = const Duration(seconds: 10),
    this.firstLinkGrace = const Duration(seconds: 30),
    this.handshakeTimeout = const Duration(seconds: 5),
    this.logger,
  }) : _checkFacts = checkFacts ?? (() async => const PlaceFacts.none()) {
    if (token.isEmpty) throw ArgumentError.value(token, 'token', 'empty');
    if (services.isEmpty) {
      throw ArgumentError.value(services, 'services', 'empty');
    }
    // Relay each hosted worker's log records to its links. Set before the
    // worker starts, since Squadron hands the logger to the channel on start.
    for (final MapEntry(key: name, value: service) in services.entries) {
      final Object worker = service;
      if (worker is IWorker) {
        worker.channelLogger = _RelayLogger(
          worker.channelLogger,
          (frame) => _relayLog(name, frame),
        );
      }
    }
    _armIdle(firstLinkGrace);
  }

  final Map<String, Invoker> services;
  final String token;
  final Duration grace;
  final Duration firstLinkGrace;
  final Duration handshakeTimeout;
  final Logger? logger;
  final Future<PlaceFacts> Function() _checkFacts;

  final _links = <_HostLink>{};
  final _running = <_Task>{};
  final _done = Completer<void>();
  Timer? _idle;

  /// Completes once the host has stopped: grace expired or [shutdown].
  Future<void> get done => _done.future;

  bool get isDone => _done.isCompleted;

  /// Number of links that passed the handshake and are still open.
  int get links => _links.length;

  /// Number of requests still running, across all links.
  int get running => _running.length;

  /// Takes over [link]: handshake, then requests until it closes.
  void accept(PlaceLink link) {
    if (isDone) {
      link.close();
      return;
    }
    _HostLink(this, link)._start();
  }

  /// Cancels every running task and stops. Idempotent.
  Future<void> shutdown([String reason = 'shutdown']) async {
    if (isDone) return;
    logger?.i('Place host stopping: $reason');
    _idle?.cancel();
    final ex = CanceledException('Place host stopped: $reason');
    for (final t in _running.toList()) {
      t.cancel(ex);
    }
    _running.clear();
    for (final l in _links.toList()) {
      await l.link.close();
    }
    _done.complete();
  }

  /// Sends a log record of service [name] to each client bound to it, once:
  /// a client with several links to the service (one per worker) would
  /// otherwise log every record once per link.
  void _relayLog(String name, List frame) {
    final sent = <Object>{};
    for (final l in _links) {
      if (l._serviceName == name && sent.add(l._client)) l._send(frame);
    }
  }

  void _armIdle(Duration after) {
    _idle?.cancel();
    _idle = Timer(after, () {
      if (_links.isEmpty) {
        shutdown('no link returned within ${after.inMilliseconds} ms');
      }
    });
  }

  void _linked(_HostLink l) {
    _idle?.cancel();
    _idle = null;
    _links.add(l);
  }

  void _unlinked(_HostLink l) {
    if (_links.remove(l) && _links.isEmpty && !isDone) _armIdle(grace);
  }

  static bool _sameToken(String a, String b) {
    // Constant-time for equal lengths; the token's length is not a secret.
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// One request being served.
class _Task {
  _Task(this.owner, this.id);

  final _HostLink owner;
  final int id;
  final token = CancelableToken();
  StreamSubscription<dynamic>? subscription;

  void cancel(CanceledException ex) {
    token.cancel(ex);
    subscription?.cancel();
    subscription = null;
  }
}

class _HostLink {
  _HostLink(this.host, this.link);

  final PlaceHost host;
  final PlaceLink link;
  late final StreamSubscription<Uint8List> _sub;
  bool _greeted = false;
  bool _helloSeen = false;
  late final Invoker _service;
  String? _serviceName;

  /// The client this link belongs to: its hello's client id, or the link
  /// itself if it sent none.
  late final Object _client;
  bool _gone = false;
  Timer? _handshake;

  /// Tasks of this link by request id, and by client token id.
  final _tasks = <int, _Task>{};
  final _byToken = <String, Set<_Task>>{};

  Logger? get _log => host.logger;

  void _start() {
    _handshake = Timer(host.handshakeTimeout, () {
      if (!_greeted) _refuse('no hello');
    });
    _sub = link.frames.listen(
      _onFrame,
      onDone: _onGone,
      onError: (_) {
        _onGone();
      },
    );
  }

  void _send(List message) {
    if (_gone) return;
    final Uint8List frame;
    try {
      frame = Msg.encode(message);
    } catch (e, st) {
      // A result the codec cannot carry: report it on the request instead.
      if (message.length > 1 && message[1] is int) {
        _send([
          Msg.error,
          message[1],
          SquadronException.from(e, st).serialize(),
        ]);
      }
      return;
    }
    link.send(frame);
  }

  void _refuse(String reason) {
    _log?.w('Place host refused a link: $reason');
    _send([Msg.refused, reason]);
    _onGone();
    link.close();
  }

  /// Largest frame accepted before the handshake: a hello is a few dozen
  /// bytes, so anything bigger is not one.
  static const maxHelloBytes = 4096;

  void _onFrame(Uint8List frame) {
    if (!_greeted) {
      if (_helloSeen) return; // one hello per link; the rest is noise
      _helloSeen = true;
      if (frame.length > maxHelloBytes) return _refuse('bad hello');
    }
    final List m;
    try {
      m = Msg.decode(frame);
    } catch (e) {
      if (_greeted) {
        _log?.w('Malformed frame: $e');
      } else {
        _refuse('bad hello');
      }
      return;
    }
    if (!_greeted) {
      _onHello(m);
      return;
    }
    try {
      _dispatch(m);
    } catch (e) {
      // A message of a known type with fields of the wrong types. Fail the
      // request it names, if any; never let it take the host down.
      _log?.w('Malformed message ${m[0]}: $e');
      final id = m.length > 1 ? m[1] : null;
      if (m[0] == Msg.request && id is int && !_tasks.containsKey(id)) {
        _send([
          Msg.error,
          id,
          WorkerException('Malformed request: $e').serialize(),
        ]);
      }
    }
  }

  void _dispatch(List m) {
    switch (m[0]) {
      case Msg.request:
        _onRequest(
          m[1] as int,
          m[2] as int,
          (m[3] as List?) ?? const [],
          m[4] as String?,
          m[5] == true,
        );
      case Msg.cancel:
        final ex = CanceledException((m[2] as String?) ?? 'canceled by client');
        for (final t in _byToken.remove(m[1]) ?? const <_Task>{}) {
          t.cancel(ex);
        }
      case Msg.unlisten:
        final t = _tasks[m[1]];
        if (t != null) {
          t.cancel(CanceledException('stream canceled by client'));
          _finish(t);
        }
      default:
        _log?.w('Unexpected message from client: ${m[0]}');
    }
  }

  Future<void> _onHello(List m) async {
    if (m[0] != Msg.hello || m.length < 3) return _refuse('expected hello');
    if (m[1] != Msg.version) return _refuse('protocol ${m[1]} unsupported');
    final token = m[2];
    if (token is! String || !PlaceHost._sameToken(token, host.token)) {
      return _refuse('bad token');
    }
    final name = m.length > 3 ? m[3] : null;
    if (name != null && name is! String) return _refuse('bad service name');
    final clientId = m.length > 4 ? m[4] : null;
    if (clientId != null && (clientId is! String || clientId.length > 128)) {
      return _refuse('bad client id');
    }
    final service = name is String
        ? host.services[name]
        : (host.services.length == 1 ? host.services.values.single : null);
    if (service == null) {
      return _refuse(
        name == null
            ? 'name a service: ${host.services.keys.join(', ')}'
            : 'unknown service $name',
      );
    }
    _service = service;
    _serviceName = name is String ? name : host.services.keys.single;
    _client = clientId ?? this;
    _greeted = true;
    _handshake?.cancel();
    host._linked(this);
    PlaceFacts facts;
    try {
      facts = await host._checkFacts();
    } catch (e) {
      _log?.w('Facts check failed: $e');
      facts = const PlaceFacts.none();
    }
    _send([Msg.welcome, Msg.version, PlaceKind.process, facts.toMap()]);
  }

  void _onRequest(
    int id,
    int command,
    List args,
    String? tokenId,
    bool streaming,
  ) {
    if (_tasks.containsKey(id)) {
      throw StateError('request id $id is already in use');
    }
    final task = _Task(this, id);
    _tasks[id] = task;
    if (tokenId != null) (_byToken[tokenId] ??= {}).add(task);
    host._running.add(task);

    if (!streaming) {
      _service
          .send(command, args: args, token: task.token)
          .then(
            (r) => _send([Msg.value, id, r]),
            onError: (Object e, StackTrace st) => _send([
              Msg.error,
              id,
              SquadronException.from(e, st, command).serialize(),
            ]),
          )
          .whenComplete(() => _finish(task));
      return;
    }

    task.subscription = _service
        .stream(command, args: args, token: task.token)
        .listen(
          (v) => _send([Msg.item, id, v]),
          onError: (Object e, StackTrace st) => _send([
            Msg.error,
            id,
            SquadronException.from(e, st, command).serialize(),
          ]),
          onDone: () {
            _send([Msg.end, id]);
            _finish(task);
          },
        );
  }

  void _finish(_Task t) {
    _tasks.remove(t.id);
    host._running.remove(t);
    for (final set in _byToken.values) {
      set.remove(t);
    }
    _byToken.removeWhere((_, set) => set.isEmpty);
  }

  /// The client went away. Its tasks keep running (hidden keeps going); only
  /// the host's grace timer can cancel them.
  void _onGone() {
    if (_gone) return;
    _gone = true;
    _handshake?.cancel();
    _sub.cancel();
    host._unlinked(this);
  }
}

/// Stands in as a hosted worker's `channelLogger`: records the worker's
/// service sends (Squadron's cross-worker logging) go to the logger that was
/// there before, if any, and out to the links bound to that service.
class _RelayLogger extends Logger {
  _RelayLogger(this._inner, this._relay)
    : super(filter: _All(), printer: _Silent(), output: _Silent());

  final Logger? _inner;
  final void Function(List frame) _relay;

  @override
  void log(
    Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _inner?.log(
      level,
      message,
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
    _relay([
      Msg.log,
      level.value,
      _stringify(message),
      (time ?? DateTime.now()).microsecondsSinceEpoch,
      error?.toString(),
      stackTrace?.toString(),
    ]);
  }

  static String _stringify(dynamic message) {
    if (message is Function) {
      try {
        return '${message()}';
      } catch (e) {
        return 'Deferred message failed with error: $e';
      }
    }
    return '$message';
  }
}

class _All extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

class _Silent extends LogPrinter implements LogOutput {
  @override
  List<String> log(LogEvent event) => const [];

  @override
  void output(OutputEvent event) {}

  @override
  Future<void> init() async {}

  @override
  Future<void> destroy() async {}
}
