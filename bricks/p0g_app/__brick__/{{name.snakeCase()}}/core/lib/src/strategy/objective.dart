import 'dart:async';

import 'package:logging/logging.dart';

import '../facts/facts.dart';
import '../log.dart';
import 'strategy.dart';

/// A plan from a [WriteStrategy], waiting for the user's confirmation.
final class Plan<I, O> {
  Plan._(this.objective, this.strategy, this.input, this.place, this.steps)
    : id = '${objective.name}-${++_counter}';

  static var _counter = 0;

  final String id;
  final Objective<I, O> objective;
  final WriteStrategy<I, O> strategy;
  final I input;
  final PlaceInfo place;
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

/// Thrown when no strategy of an objective fits a place.
final class NoStrategyAvailable implements Exception {
  const NoStrategyAvailable(this.objective, this.place, this.why);

  final String objective;
  final PlaceInfo place;
  final String why;

  @override
  String toString() => 'NoStrategyAvailable: $objective in $place: $why';
}

/// Something the app wants done, and the strategies that can do it, in
/// preference order.
///
/// The first strategy whose `available(facts)` accepts the place's facts
/// runs. Every run is logged as a [StrategyRun] (see `log.dart`).
final class Objective<I, O> {
  Objective(this.name, this.strategies) : _log = Logger('objective.$name');

  final String name;
  final List<Strategy<I, O>> strategies;
  final Logger _log;

  /// Which read strategy would run in [place], and why.
  Selection<ReadStrategy<I, O>> selectRead(PlaceInfo place) =>
      Selection(strategies.whereType<ReadStrategy<I, O>>(), place.facts);

  /// Which write strategy would plan in [place], and why.
  Selection<WriteStrategy<I, O>> selectWrite(PlaceInfo place) =>
      Selection(strategies.whereType<WriteStrategy<I, O>>(), place.facts);

  S _chosen<S extends Strategy<I, O>>(Selection<S> s, PlaceInfo place) {
    final chosen = s.chosen;
    _log.fine('in $place: ${s.why}');
    if (chosen == null) throw NoStrategyAvailable(name, place, s.why);
    return chosen;
  }

  /// Run the first available [ReadStrategy].
  Future<O> run(I input, PlaceInfo place) {
    final selection = selectRead(place);
    final s = _chosen(selection, place);
    return _record(s, place, selection.why, () => s.run(input, place));
  }

  /// Plan with the first available [WriteStrategy]. Changes nothing.
  Future<Plan<I, O>> plan(I input, PlaceInfo place) async {
    final s = _chosen(selectWrite(place), place);
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
      'confirmed ${plan.id}',
      () => plan.strategy.write(plan.input, plan.place),
      onRun: (r) => run = r,
    );
    return Receipt(run, plan.steps, result);
  }

  Future<R> _record<R>(
    Strategy<I, O> s,
    PlaceInfo place,
    String why,
    Future<R> Function() body, {
    void Function(StrategyRun)? onRun,
  }) async {
    final watch = Stopwatch()..start();
    StrategyRun done(String outcome) {
      final r = StrategyRun(
        objective: name,
        strategy: s.name,
        place: place.kind,
        facts: place.facts.present,
        write: s is WriteStrategy,
        why: why,
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
