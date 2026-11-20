/// Unofficial Squadron extension: a third place to run a Squadron service
/// (another, optionally elevated, process) and the facts each place reports.
///
/// Requires the patched Squadron in `third_party/squadron` (see
/// `tool/squadron.sh`).
library;

export 'src/codec.dart' show PlaceCodec;
export 'src/facts.dart';
export 'src/launcher.dart';
export 'src/link.dart';
export 'src/place.dart';
export 'src/process_channel.dart';
