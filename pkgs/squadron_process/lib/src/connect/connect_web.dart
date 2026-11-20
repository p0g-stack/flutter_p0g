import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../launcher.dart';
import '../link.dart';

/// Connects to a place host with the browser's WebSocket (binary frames).
Future<PlaceLink> connectWebSocket(ProcessEndpoint endpoint) {
  final socket = web.WebSocket(endpoint.uri.toString())
    ..binaryType = 'arraybuffer';
  final opened = Completer<PlaceLink>();
  final link = _WebSocketLink(socket);
  socket.onopen = ((web.Event _) => opened.complete(link)).toJS;
  socket.onerror = ((web.Event _) {
    if (!opened.isCompleted) {
      opened.completeError(
        StateError('WebSocket to ${endpoint.uri} failed to open'),
      );
    }
  }).toJS;
  return opened.future;
}

class _WebSocketLink implements PlaceLink {
  _WebSocketLink(this._socket) {
    _socket.onmessage = ((web.MessageEvent e) {
      final data = e.data;
      if (data.isA<JSArrayBuffer>()) {
        _frames.add((data as JSArrayBuffer).toDart.asUint8List());
      }
    }).toJS;
    _socket.onclose = ((web.Event _) {
      if (!_frames.isClosed) _frames.close();
    }).toJS;
  }

  final web.WebSocket _socket;
  final _frames = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  void send(Uint8List frame) {
    if (_socket.readyState == web.WebSocket.OPEN) _socket.send(frame.toJS);
  }

  @override
  Future<void> close() async {
    _socket.close();
    if (!_frames.isClosed) _frames.close();
  }
}
