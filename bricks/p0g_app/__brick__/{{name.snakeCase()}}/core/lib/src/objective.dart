import 'dart:async';

import 'package:logging/logging.dart';

import 'facts.dart';
import 'log.dart';
import 'place.dart';

/// One way to reach an objective, usable only where [available] says so.
///
/// Strategies decide from the facts of the place they would run in, never from
/// `kIsWeb` or `Platform`. Host-versus-device choices are strategies too: an
/// on-device `dd` and a host-side `fastboot fetch` are two strategies of one
/// `fetch` objective.
sealed class Strategy<I, O> {
  const Strategy();

  /// A short, stable name for logs ("dd", "fastboot_fetch").
  String get name;

  /// Whether this strategy can run in a place with these [facts].
  bool available(Facts facts);
}

/// A strategy that changes nothing on the device. It just runs.
abstract base class ReadStrategy<I, O> extends Strategy<I, O> {
  const ReadStrategy();

  Future<O> run(I input, Place place);
}

/// A strategy that writes to a device: plan, then confirm, then receipt.
///
/// [plan] must not change anything. [write] runs only through
/// [Objective.apply], which checks that the user confirmed this exact plan.
abstract base class WriteStrategy<I, O> extends Strategy<I, O> {
  const WriteStrategy();

  /// Describe, step by step, what [write] would do. No side effects.
  Future<List<String>> plan(I input, Place place);

  /// Do what the plan said.
  Future<O> write(I input, Place place);
}

/// A plan from a [WriteStrategy], waiting for the user's confirmation.
final class Plan<I, O> {
  Plan._(this.objective, this.strategy, this.input, this.place, this.steps)
    : id = '${objective.name}-${++_counter}';

  static var _counter = 0;

  final String id;
  final Objective<I, O> objective;
  final WriteStrategy<I, O> strategy;
  final I input;
  final Place place;
  final List<String> steps;
}

/// The user's yes to one [Plan]. The UI or CLI makes it after showing the
/// steps; nothing else should.
final class Confirmation {
  Confirmation.of(Plan<Object?, Object?> plan)
    : planId = plan.id,
      at = DateTime.now();

  final String planId;
  final DateTime at;
}

/// What a confirmed write did.
final class Receipt<O> {
  const Receipt(this.run, this.steps, this.result);

  final StrategyRun run;
  final List<String> steps;
  final O result;
}

/// Thrown when no strategy of an objective is available in a place.
final class NoStrategyAvailable implements Exception {
  const NoStrategyAvailable(this.objective, this.place, this.candidates);

  final String objective;
  final Place place;
  final List<String> candidates;

  @override
  String toString() =>
      'NoStrategyAvailable: no strategy for "$objective" in $place '
      '(tried ${candidates.join(', ')}; facts: ${place.facts.present})';
}

/// Something the app wants done, and the ordered strategies that can do it.
///
/// The first strategy whose [Strategy.available] accepts the place's facts
/// runs. Every run is logged as a [StrategyRun] (see `log.dart`).
final class Objective<I, O> {
  Objective(this.name, this.strategies) : _log = Logger('objective.$name');

  final String name;
  final List<Strategy<I, O>> strategies;
  final Logger _log;

  /// The strategies usable in [place], in order.
  List<Strategy<I, O>> availableIn(Place place) => [
    for (final s in strategies)
      if (s.available(place.facts)) s,
  ];

  T _pick<T extends Strategy<I, O>>(Place place) {
    for (final s in strategies.whereType<T>()) {
      if (s.available(place.facts)) return s;
    }
    final candidates = [for (final s in strategies.whereType<T>()) s.name];
    _log.fine('no $T available in $place, tried $candidates');
    throw NoStrategyAvailable(name, place, candidates);
  }

  /// Run the first available [ReadStrategy].
  Future<O> run(I input, Place place) {
    final s = _pick<ReadStrategy<I, O>>(place);
    return _record(s, place, () => s.run(input, place));
  }

  /// Plan with the first available [WriteStrategy]. Changes nothing.
  Future<Plan<I, O>> plan(I input, Place place) async {
    final s = _pick<WriteStrategy<I, O>>(place);
    final steps = await s.plan(input, place);
    _log.info('planned ${s.name} in $place: ${steps.length} steps');
    return Plan._(this, s, input, place, List.unmodifiable(steps));
  }

  /// Carry out a confirmed [plan] and return its receipt.
  Future<Receipt<O>> apply(Plan<I, O> plan, Confirmation confirmation) async {
    if (!identical(plan.objective, this) || confirmation.planId != plan.id) {
      throw StateError(
        'confirmation ${confirmation.planId} is not for ${plan.id}',
      );
    }
    late StrategyRun run;
    final result = await _record(
      plan.strategy,
      plan.place,
      () => plan.strategy.write(plan.input, plan.place),
      onRun: (r) => run = r,
    );
    return Receipt(run, plan.steps, result);
  }

  Future<R> _record<R>(
    Strategy<I, O> s,
    Place place,
    Future<R> Function() body, {
    void Function(StrategyRun)? onRun,
  }) async {
    final watch = Stopwatch()..start();
    StrategyRun done(String outcome) {
      final r = StrategyRun(
        objective: name,
        strategy: s.name,
        place: place.name,
        facts: place.facts.present,
        write: s is WriteStrategy,
        outcome: outcome,
        elapsed: watch.elapsed,
      );
      onRun?.call(r);
      return r;
    }

    try {
      final result = await body();
      _log.info(done('ok'));
      return result;
    } catch (e, st) {
      _log.warning(done('error'), e, st);
      rethrow;
    }
  }
}
