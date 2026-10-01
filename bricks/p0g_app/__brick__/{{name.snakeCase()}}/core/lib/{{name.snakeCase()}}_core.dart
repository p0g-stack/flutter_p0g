/// The logic of {{name.snakeCase()}}, shared by the Flutter app and the CLI.
///
/// Pure Dart: this library never imports `package:flutter`, because the CLI
/// runs it on the plain Dart VM.
library;

export 'package:logging/logging.dart' show Level, LogRecord, Logger;

export 'src/facts.dart';
export 'src/log.dart';
export 'src/objective.dart';
export 'src/place.dart';
export 'src/services/hello_service.dart';

// p0g:exports (bricks insert exports above this line)
