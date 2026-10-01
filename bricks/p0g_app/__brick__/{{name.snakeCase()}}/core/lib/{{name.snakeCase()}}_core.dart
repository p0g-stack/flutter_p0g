/// The logic of {{name.snakeCase()}}, shared by the Flutter app, its workers
/// and the CLI.
///
/// Pure Dart: this library never imports `package:flutter`, because the CLI
/// runs it on the plain Dart VM.
library;

export 'package:logging/logging.dart' show Level, LogRecord, Logger;

export 'src/facts/facts.dart';
export 'src/log.dart';
{{#rust}}export 'src/native/native.dart' show loadNative, sha256Hex;
{{/rust}}export 'src/places/webui_launcher.dart';
export 'src/service/hello_service.dart';
{{#rust}}export 'src/strategy/digest.dart';
{{/rust}}export 'src/strategy/objective.dart';
export 'src/strategy/strategy.dart';
// p0g:exports (bricks insert exports above this line)
