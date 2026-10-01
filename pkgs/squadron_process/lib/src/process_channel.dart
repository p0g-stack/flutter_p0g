import 'dart:async';
import 'dart:typed_data';

import 'package:logger/web.dart';
import 'package:squadron/squadron.dart';

import 'facts.dart';
import 'link.dart';
import 'protocol.dart';

/// A link that passed the handshake, with what the host said about its place.
class ProcessHandshake {
  ProcessHandshake._(this.link, this.place, this.facts);

  /// The link after the welcome; requests go over it.
  final PlaceLink link;

  /// The kind of place the host reported (`process`).
  final String place;

  /// The facts the host checked when it accepted the link.
  final PlaceFacts facts;

  /// Runs the handshake over [link]: sends hello with [token] and the
  /// [service] name (null: the host's only service), and waits for the host's
  /// welcome. Throws [WorkerException] if the host refuses, answers with
  /// something that is not a welcome, or does not answer within [timeout];
  /// the link is closed in that case.
  static Future<ProcessHandshake> run(
    PlaceLink link, {
    required String token,
    String? service,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final frames = StreamIterator(link.frames);
    try {
      link.send(Msg.encode([Msg.hello, Msg.version, token, service]));
      if (!await frames.moveNext().timeout(timeout)) {
        throw WorkerException('Place host closed the link during handshake');
      }
      final List m;
      try {
        m = Msg.decode(frames.current);
      } on FormatException catch (e) {
        throw WorkerException('Malformed handshake from place host: $e');
      }
      if (m[0] == Msg.refused) {
        throw WorkerException(
          'Place host refused the link: ${m.length > 1 ? m[1] : '?'}',
        );
      }
      if (m[0] != Msg.welcome ||
          m.length < 4 ||
          m[1] != Msg.version ||
          m[2] is! String ||
          m[3] is! Map) {
        throw WorkerException('Unexpected handshake from place host: $m');
      }
      return ProcessHandshake._(
        _RestOf(frames, link),
        m[2] as String,
        PlaceFacts.fromMap(m[3] as Map),
      );
    } on TimeoutException {
      await frames.cancel();
      await link.close();
      throw WorkerException('Place host did not answer the handshake');
    } catch (_) {
      await frames.cancel();
      await link.close();
      rethrow;
    }
  }
}

/// Opens a fresh, handshaken link to the same service, for a channel whose
/// link dropped.
typedef Reconnect = Future<ProcessHandshake> Function();

/// A Squadron [Channel] to a service hosted in another process, over a
/// [PlaceLink].
///
/// Opened by [ProcessChannel.connect], which runs the handshake: the client
/// presents the host's token and the host answers with the facts of its place.
/// [Worker.start] reaches it through a channel factory (see `ProcessPlace`).
///
/// If the link drops, calls in flight fail with a [WorkerException]. With a
/// [Reconnect], the channel stays usable: the next call opens a new link
/// (which may start a new host) and goes over it, so the worker that owns the
/// channel keeps working. Without one, the channel is closed for good.
class ProcessChannel implements Channel {
  ProcessChannel._(
    ProcessHandshake handshake,
    this.exceptionManager,
    this.logger,
    this._reconnect,
  ) {
    _attach(handshake);
  }

  /// Connects over [link] (see [ProcessHandshake.run]) and returns the
  /// channel. [reconnect], if given, replaces the link after it drops.
  static Future<ProcessChannel> connect(
    PlaceLink link, {
    required String token,
    String? service,
    ExceptionManager? exceptionManager,
    Logger? logger,
    Duration timeout = const Duration(seconds: 10),
    Reconnect? reconnect,
  }) async => ProcessChannel.fromHandshake(
    await ProcessHandshake.run(
      link,
      token: token,
      service: service,
      timeout: timeout,
    ),
    exceptionManager: exceptionManager,
    logger: logger,
    reconnect: reconnect,
  );

  /// A channel over a link that already passed the handshake.
  factory ProcessChannel.fromHandshake(
    ProcessHandshake handshake, {
    ExceptionManager? exceptionManager,
    Logger? logger,
    Reconnect? reconnect,
  }) => ProcessChannel._(
    handshake,
    exceptionManager ?? ExceptionManager(),
    logger,
    reconnect,
  );

  final Reconnect? _reconnect;
  PlaceLink? _link;
  StreamSubscription<Uint8List>? _sub;
  Future<void>? _reconnecting;
  late String _place;
  late PlaceFacts _facts;

  /// The kind of place the host reported (`process`).
  String get place => _place;

  /// The facts the host checked when the current link was accepted.
  PlaceFacts get facts => _facts;

  /// Whether a link is up right now. A channel with a [Reconnect] can be
  /// unlinked and still usable.
  bool get isLinked => _link != null;

  @override
  final ExceptionManager exceptionManager;

  @override
  final Logger? logger;

  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _streams = <int, StreamController<dynamic>>{};
  final _closed = Completer<void>();
  String? _lostReason;

  /// Closed for good: [close] was called, or the link dropped and there is no
  /// [Reconnect].
  bool get isClosed => _closed.isCompleted;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> close() {
    if (!_closed.isCompleted) {
      final link = _link;
      _lost('channel closed');
      _closed.complete();
      link?.close();
    }
    return _closed.future;
  }

  /// A process channel cannot be handed to another worker: it is a socket in
  /// this context, not a transferable port.
  @override
  PlatformChannel serialize() =>
      throw UnsupportedError('A process channel cannot be serialized');

  @override
  Channel share() => this;

  @override
  void cancelToken(SquadronCancelationToken? token) {
    // Tokens belong to calls on the current link; without one there is
    // nothing in flight to cancel.
    if (token == null || _link == null) return;
    _send([Msg.cancel, token.id, token.exception?.message]);
  }

  @override
  void cancelStream(StreamId streamId) {
    // Streams are cancelled through their subscription (see onCancel below);
    // Squadron's StreamId is never exposed to callers of this channel.
  }

  @override
  Future<dynamic> sendRequest(
    int command,
    List args, {
    SquadronCancelationToken? token,
    bool inspectRequest = false,
    bool inspectResponse = false,
  }) {
    _throwIfClosed(command);
    final id = _nextId++;
    // Encode first: arguments the link cannot carry fail this call only.
    final frame = _encode([
      Msg.request,
      id,
      command,
      args,
      token?.id,
      false,
    ], command);
    if (_link != null) return _request(id, frame);
    return _linked(command).then((_) => _request(id, frame));
  }

  Future<dynamic> _request(int id, Uint8List frame) {
    final c = Completer<dynamic>();
    _pending[id] = c;
    _link!.send(frame);
    return c.future;
  }

  @override
  Stream<dynamic> sendStreamingRequest(
    int command,
    List args, {
    SquadronCancelationToken? token,
    bool inspectRequest = false,
    bool inspectResponse = false,
  }) {
    late final StreamController<dynamic> controller;
    int? id;
    var canceled = false;

    void start() {
      if (canceled) return;
      id = _nextId++;
      final Uint8List frame;
      try {
        frame = _encode([
          Msg.request,
          id,
          command,
          args,
          token?.id,
          true,
        ], command);
      } catch (e) {
        controller.addError(e);
        controller.close();
        return;
      }
      _streams[id!] = controller;
      _link!.send(frame);
    }

    void fail(Object e) {
      controller.addError(e);
      controller.close();
    }

    controller = StreamController<dynamic>(
      onListen: () {
        if (isClosed) return fail(_lostError(command));
        if (_link != null) return start();
        _linked(command).then((_) => start(), onError: fail);
      },
      onCancel: () {
        canceled = true;
        final i = id;
        if (i != null && _streams.remove(i) != null) _send([Msg.unlisten, i]);
      },
    );
    return controller.stream;
  }

  /// Completes once a link is up, opening a new one if the last dropped.
  Future<void> _linked(int command) {
    final reconnect = _reconnect;
    if (reconnect == null) return Future.error(_lostError(command));
    return _reconnecting ??= () async {
      try {
        logger?.i('Process place link is gone ($_lostReason); reconnecting');
        final handshake = await reconnect();
        if (isClosed) {
          await handshake.link.close();
          throw _lostError(command);
        }
        _attach(handshake);
      } finally {
        _reconnecting = null;
      }
    }();
  }

  void _attach(ProcessHandshake handshake) {
    final link = handshake.link;
    _place = handshake.place;
    _facts = handshake.facts;
    _link = link;
    _lostReason = null;
    _sub = link.frames.listen(
      _onFrame,
      onError: (Object e) => _dropped(link, 'link error: $e'),
      onDone: () => _dropped(link, 'link closed'),
    );
  }

  void _dropped(PlaceLink link, String reason) {
    if (!identical(link, _link)) return;
    _lost(reason);
    if (_reconnect == null && !_closed.isCompleted) _closed.complete();
  }

  void _send(List message) => _link?.send(Msg.encode(message));

  Uint8List _encode(List message, int command) {
    try {
      return Msg.encode(message);
    } catch (e, st) {
      throw WorkerException(
        'Arguments cannot cross the process link: $e',
        st,
        command,
      );
    }
  }

  void _throwIfClosed(int command) {
    if (isClosed) throw _lostError(command);
  }

  WorkerException _lostError([int? command]) => WorkerException(
    'Process place link is gone (${_lostReason ?? 'closed'})',
    null,
    command,
  );

  void _onFrame(Uint8List frame) {
    final List m;
    try {
      m = Msg.decode(frame);
    } catch (e) {
      logger?.w('Dropping malformed frame from place host: $e');
      return;
    }
    final id = m.length > 1 ? m[1] : null;
    final payload = m.length > 2 ? m[2] : null;
    switch (m[0]) {
      case Msg.value:
        _pending.remove(id)?.complete(payload);
      case Msg.error:
        final ex =
            (payload is List
                ? exceptionManager.deserialize(payload.cast())
                : null) ??
            WorkerException('Unknown error from place host');
        final c = _pending.remove(id);
        if (c != null) {
          c.completeError(ex);
        } else {
          _streams[id]?.addError(ex);
        }
      case Msg.item:
        _streams[id]?.add(payload);
      case Msg.end:
        _streams.remove(id)?.close();
      default:
        logger?.w('Unexpected message from place host: ${m[0]}');
    }
  }

  /// The current link is gone: fail what was in flight on it.
  void _lost(String reason) {
    if (_link == null) return;
    _lostReason = reason;
    _link = null;
    _sub?.cancel();
    _sub = null;
    final ex = _lostError();
    for (final c in _pending.values) {
      c.completeError(ex);
    }
    _pending.clear();
    for (final s in _streams.values) {
      s.addError(ex);
      s.close();
    }
    _streams.clear();
  }
}

/// The link after the handshake: the rest of an already-started frame stream.
class _RestOf implements PlaceLink {
  _RestOf(this._frames, this._link);

  final StreamIterator<Uint8List> _frames;
  final PlaceLink _link;

  @override
  Stream<Uint8List> get frames async* {
    while (await _frames.moveNext()) {
      yield _frames.current;
    }
  }

  @override
  void send(Uint8List frame) => _link.send(frame);

  @override
  Future<void> close() async {
    await _link.close();
    await _frames.cancel();
  }
}
