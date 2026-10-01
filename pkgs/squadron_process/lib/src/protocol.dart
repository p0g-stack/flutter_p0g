import 'dart:typed_data';

import 'codec.dart';

/// Wire messages of the process place. Every frame is one [PlaceCodec] list
/// whose first element is the message type.
///
/// ```
/// client -> host                     host -> client
/// hello    [0, version, token,       welcome  [10, version, place, facts]
///           service?, clientId?]
/// request  [1, id, cmd, args,        refused  [11, reason]
///           tokenId?, streaming]     value    [12, id, result]
/// cancel   [2, tokenId, message?]    error    [13, id, exception]
/// unlisten [3, id]                   item     [14, id, value]
///                                    end      [15, id]
///                                    log      [16, level, message,
///                                              timeUs, error?, stack?]
/// ```
///
/// `log` relays a log record of the service the link is bound to (what
/// Squadron's own channels deliver to a worker's `channelLogger`), once per
/// client: to one link per `clientId` (a link without one is its own client). `level` is
/// package:logger's `Level.value`; `timeUs` is microseconds since the epoch.
/// A client that does not know it ignores it.
///
/// `exception` is `SquadronException.serialize()`, so a client's
/// `ExceptionManager` rebuilds custom exceptions the same way it does for
/// isolates and Web Workers.
abstract final class Msg {
  static const version = 1;

  static const hello = 0;
  static const request = 1;
  static const cancel = 2;
  static const unlisten = 3;

  static const welcome = 10;
  static const refused = 11;
  static const value = 12;
  static const error = 13;
  static const item = 14;
  static const end = 15;
  static const log = 16;

  static Uint8List encode(List message) => PlaceCodec.encode(message);

  /// Decodes a frame; throws [FormatException] if it is not a message.
  static List decode(Uint8List frame) {
    final m = PlaceCodec.decode(frame);
    if (m is! List || m.isEmpty || m[0] is! int) {
      throw const FormatException('not a place message');
    }
    return m;
  }
}
