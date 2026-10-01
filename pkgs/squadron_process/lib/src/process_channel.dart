import 'dart:async';
import 'dart:typed_data';

import 'package:logger/web.dart';
import 'package:squadron/squadron.dart';

import 'facts.dart';
import 'link.dart';
import 'protocol.dart';

/// A Squadron [Channel] to a service hosted in another process, over a
/// [PlaceLink].
///
/// Opened by [ProcessChannel.connect], which runs the handshake: the client
/// presents the host's token and the host answers with the facts of its place.
/// [Worker.start] reaches it through a channel factory (see `ProcessPlace`).
class ProcessChannel implements Channel {
  ProcessChannel._(
    this._link,
    this.exceptionManager,
    this.logger,
    this.place,
    this.facts,
  ) {
    _sub = _link.frames.listen(
      _onFrame,
      onError: (Object e) => _lost('link error: $e'),
      onDone: () => _lost('link closed'),
    );
  }

  /// Connects over [link]: sends hello with [token] and waits for the host's
  /// welcome. Throws [WorkerException] if the host refuses or does not answer
  /// within [timeout]; the link is closed in that case.
  static Future<ProcessChannel> connect(
    PlaceLink link, {
    required String token,
    ExceptionManager? exceptionManager,
    Logger? logger,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final frames = StreamIterator(link.frames);
    try {
      link.send(Msg.encode([Msg.hello, Msg.version, token]));
      if (!await frames.moveNext().timeout(timeout)) {
        throw WorkerException('Place host closed the link during handshake');
      }
      final m = Msg.decode(frames.current);
      if (m[0] == Msg.refused) {
        throw WorkerException('Place host refused the link: ${m[1]}');
      }
      if (m[0] != Msg.welcome || m[1] != Msg.version) {
        throw WorkerException('Unexpected handshake from place host: $m');
      }
      final channel = ProcessChannel._(
        _RestOf(frames, link),
        exceptionManager ?? ExceptionManager(),
        logger,
        m[2] as String,
        PlaceFacts.fromMap(m[3] as Map),
      );
      return channel;
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

  final PlaceLink _link;
  late final StreamSubscription<Uint8List> _sub;

  /// The kind of place the host reported (`process`).
  final String place;

  /// The facts the host checked when this link was accepted.
  final PlaceFacts facts;

  @override
  final ExceptionManager exceptionManager;

  @override
  final Logger? logger;

  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _streams = <int, StreamController<dynamic>>{};
  final _closed = Completer<void>();
  String? _lostReason;

  bool get isClosed => _closed.isCompleted;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> close() {
    if (!_closed.isCompleted) {
      _lost('channel closed');
      _link.close();
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
    if (token == null || isClosed) return;
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
    final c = Completer<dynamic>();
    _pending[id] = c;
    _link.send(frame);
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
    late final int id;
    controller = StreamController<dynamic>(
      onListen: () {
        if (isClosed) {
          controller.addError(_lostError(command));
          controller.close();
          return;
        }
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
        _streams[id] = controller;
        _link.send(frame);
      },
      onCancel: () {
        if (_streams.remove(id) != null) _send([Msg.unlisten, id]);
      },
    );
    return controller.stream;
  }

  void _send(List message) => _link.send(Msg.encode(message));

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
    switch (m[0]) {
      case Msg.value:
        _pending.remove(id)?.complete(m[2]);
      case Msg.error:
        final ex =
            exceptionManager.deserialize((m[2] as List).cast()) ??
            WorkerException('Unknown error from place host');
        final c = _pending.remove(id);
        if (c != null) {
          c.completeError(ex);
        } else {
          _streams[id]?.addError(ex);
        }
      case Msg.item:
        _streams[id]?.add(m[2]);
      case Msg.end:
        _streams.remove(id)?.close();
      default:
        logger?.w('Unexpected message from place host: ${m[0]}');
    }
  }

  void _lost(String reason) {
    if (_closed.isCompleted) return;
    _lostReason = reason;
    _sub.cancel();
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
    _closed.complete();
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
