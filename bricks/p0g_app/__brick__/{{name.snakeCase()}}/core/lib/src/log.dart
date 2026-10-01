import 'dart:convert';

import 'package:logger/web.dart' as squadron_log;
import 'package:logging/logging.dart';
import 'package:squadron/squadron.dart';

/// The logging convention.
///
/// Every objective logs one [StrategyRun] per run on the `objective.<name>`
/// logger, as the record's `object`, so sinks can say "fetched via dd in the
/// root process, fastboot skipped (missing usb.native)" instead of guessing. Services and commands log to loggers
/// named after themselves (`service.hello`, `cli.serve`).
final class StrategyRun {
  const StrategyRun({
    required this.objective,
    required this.strategy,
    required this.place,
    required this.facts,
    required this.write,
    required this.why,
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

  /// Which strategies were skipped and why.
  final String why;

  /// `ok` or `error`.
  final String outcome;
  final Duration elapsed;

  Map<String, Object?> toJson() => {
    'objective': objective,
    'strategy': strategy,
    'place': place,
    'facts': facts,
    'write': write,
    'why': why,
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

/// Sends this isolate's or Web Worker's records to whoever started it.
///
/// Records are per isolate, so a service's logs (`service.*`, the
/// `objective.*` runs) would otherwise reach no sink. Call this in the
/// service's constructor, which runs where the service runs; Squadron carries
/// the records over its channel and [withLogs] on the caller's worker logs
/// them there under their own logger names, at the caller's level. The
/// caller's level filters them; here everything goes.
void forwardLogs() {
  if (_forwarding) return;
  _forwarding = true;
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(
    (r) => _squadronSide.log(
      _toSquadron(r.level),
      '${r.loggerName}\t${r.message}',
      error: r.error,
      stackTrace: r.stackTrace,
    ),
  );
}

bool _forwarding = false;

/// Logs the records [worker]'s service sends with [forwardLogs]. Set it on
/// every worker before it starts: `place.bind(withLogs(MyServiceWorker()))`.
W withLogs<W extends Worker>(W worker) => worker..channelLogger = _callerSide;

/// Squadron forwards whatever a package:logger logger outputs in a worker.
final _squadronSide = squadron_log.Logger(
  filter: _Everything(),
  printer: _Mark(),
  output: _Nowhere(),
);

/// Turns what arrives back into package:logging records.
final _callerSide = squadron_log.Logger(
  filter: _Everything(),
  printer: _Relog(),
  output: _Nowhere(),
);

final class _Everything extends squadron_log.LogFilter {
  @override
  bool shouldLog(squadron_log.LogEvent event) => true;
}

/// Output must be non-empty for the listeners (Squadron's) to see the event.
final class _Mark extends squadron_log.LogPrinter {
  @override
  List<String> log(squadron_log.LogEvent event) => const [''];
}

final class _Relog extends squadron_log.LogPrinter {
  @override
  List<String> log(squadron_log.LogEvent event) {
    final text = '${event.message}';
    final tab = text.indexOf('\t');
    Logger(tab < 0 ? 'worker' : text.substring(0, tab)).log(
      _fromSquadron(event.level),
      tab < 0 ? text : text.substring(tab + 1),
      event.error,
      event.stackTrace,
      null,
    );
    return const [];
  }
}

final class _Nowhere extends squadron_log.LogOutput {
  @override
  void output(squadron_log.OutputEvent event) {}
}

squadron_log.Level _toSquadron(Level l) => switch (l.value) {
  < 500 => squadron_log.Level.trace, // FINER, FINEST
  < 800 => squadron_log.Level.debug, // FINE, CONFIG
  < 900 => squadron_log.Level.info,
  < 1000 => squadron_log.Level.warning,
  < 1200 => squadron_log.Level.error, // SEVERE
  _ => squadron_log.Level.fatal, // SHOUT
};

Level _fromSquadron(squadron_log.Level l) => switch (l) {
  squadron_log.Level.trace || squadron_log.Level.all => Level.FINEST,
  squadron_log.Level.debug => Level.FINE,
  squadron_log.Level.info => Level.INFO,
  squadron_log.Level.warning => Level.WARNING,
  squadron_log.Level.error => Level.SEVERE,
  _ => Level.SHOUT,
};
