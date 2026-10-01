import 'dart:convert';

import 'package:logging/logging.dart';

/// The logging convention.
///
/// Every objective logs one [StrategyRun] per run on the `objective.<name>`
/// logger, as the record's `object`, so sinks can say "fetched via dd in the
/// root process" instead of guessing. Services and commands log to loggers
/// named after themselves (`service.hello`, `cli.serve`).
final class StrategyRun {
  const StrategyRun({
    required this.objective,
    required this.strategy,
    required this.place,
    required this.facts,
    required this.write,
    required this.outcome,
    required this.elapsed,
  });

  final String objective;
  final String strategy;
  final String place;

  /// The facts that were true where it ran.
  final List<String> facts;

  /// Whether it was a confirmed device write.
  final bool write;

  /// `ok` or `error`.
  final String outcome;
  final Duration elapsed;

  Map<String, Object?> toJson() => {
    'objective': objective,
    'strategy': strategy,
    'place': place,
    'facts': facts,
    'write': write,
    'outcome': outcome,
    'elapsed_ms': elapsed.inMilliseconds,
  };

  @override
  String toString() =>
      '$objective: ${write ? 'wrote' : 'ran'} $strategy in $place '
      '[${facts.join(', ')}] $outcome in ${elapsed.inMilliseconds}ms';
}

/// One line per record: time, level, logger, message; `--json` style sinks
/// can use [recordToJson] instead.
String formatRecord(LogRecord r) {
  final b = StringBuffer(
    '${r.time.toIso8601String()} ${r.level.name} ${r.loggerName}: ${r.message}',
  );
  if (r.error != null) b.write(' (${r.error})');
  return b.toString();
}

Map<String, Object?> recordToJson(LogRecord r) => {
  'time': r.time.toIso8601String(),
  'level': r.level.name,
  'logger': r.loggerName,
  'message': r.message,
  if (r.object is StrategyRun) 'run': (r.object! as StrategyRun).toJson(),
  if (r.error != null) 'error': '${r.error}',
};

/// Send every record at [level] or above to [sink]. Returns a function that
/// stops it.
void Function() logTo(
  void Function(String line) sink, {
  Level level = Level.INFO,
  bool json = false,
}) {
  Logger.root.level = level;
  final sub = Logger.root.onRecord.listen(
    (r) => sink(json ? jsonEncode(recordToJson(r)) : formatRecord(r)),
  );
  return sub.cancel;
}
