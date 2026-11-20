import 'dart:async';
import 'dart:typed_data';

/// One duplex connection between a client and a place host, carrying whole
/// binary frames. The WebSocket link is the real one; tests use
/// [PlaceLink.pair].
abstract interface class PlaceLink {
  /// Frames from the other end. Done when the link closes, from either end.
  Stream<Uint8List> get frames;

  /// Sends one frame. Frames sent after [close] are dropped.
  void send(Uint8List frame);

  /// Closes the link. Idempotent.
  Future<void> close();

  /// Two in-memory ends of one link.
  static (PlaceLink, PlaceLink) pair() {
    final a = StreamController<Uint8List>();
    final b = StreamController<Uint8List>();
    final left = _MemoryLink(a, b);
    final right = _MemoryLink(b, a);
    left._peer = right;
    right._peer = left;
    return (left, right);
  }
}

class _MemoryLink implements PlaceLink {
  _MemoryLink(this._in, this._out);

  final StreamController<Uint8List> _in;
  final StreamController<Uint8List> _out;
  late final _MemoryLink _peer;
  bool _closed = false;

  @override
  Stream<Uint8List> get frames => _in.stream;

  @override
  void send(Uint8List frame) {
    if (_closed) return;
    // Copy, like a socket would: the receiver must not share our buffer.
    _out.add(Uint8List.fromList(frame));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _peer._closed = true;
    // Not awaited: a controller's done future waits for a listener.
    _in.close();
    _out.close();
  }
}
