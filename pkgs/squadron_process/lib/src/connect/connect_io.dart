import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../launcher.dart';
import '../link.dart';

/// Connects to a place host with a `dart:io` WebSocket.
Future<PlaceLink> connectWebSocket(ProcessEndpoint endpoint) async =>
    IoWebSocketLink(await WebSocket.connect(endpoint.uri.toString()));

/// A [PlaceLink] over a `dart:io` [WebSocket]; used by clients and hosts.
class IoWebSocketLink implements PlaceLink {
  IoWebSocketLink(this._socket);

  final WebSocket _socket;
  bool _closed = false;

  @override
  late final Stream<Uint8List> frames = _socket
      .where((data) => data is List<int>)
      .map((data) => data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void send(Uint8List frame) {
    if (_closed || _socket.readyState != WebSocket.open) return;
    _socket.add(frame);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
  }
}
