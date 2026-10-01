import '../facts/facts.dart';

/// One way to reach an objective, usable only where its facts allow.
///
/// Strategies decide with [available], never with `kIsWeb` or `Platform`.
/// Host-versus-device choices are strategies too: an on-device `dd` and a
/// host-side `fastboot fetch` are two strategies of one `fetch` objective.
sealed class Strategy<I, O> {
  const Strategy();

  /// A short, stable name for logs (`dd`, `fastboot_fetch`).
  String get name;

  /// Facts this strategy cannot run without.
  Set<String> get requires => const {};

  /// Whether this strategy can run in a place with [facts], and if not, why.
  /// Override for conditions beyond [requires].
  Availability available(Facts facts) =>
      Availability(name, missing: facts.missing(requires));
}

/// A strategy that changes nothing on the device. It just runs.
abstract base class ReadStrategy<I, O> extends Strategy<I, O> {
  const ReadStrategy();

  Future<O> run(I input, PlaceInfo place);
}

/// A strategy that writes to a device: plan, then confirm, then receipt.
///
/// [plan] must not change anything. [write] runs only through
/// `Objective.apply`, which checks that the user confirmed this exact plan.
abstract base class WriteStrategy<I, O> extends Strategy<I, O> {
  const WriteStrategy();

  /// Describe, step by step, what [write] would do. No side effects.
  Future<List<String>> plan(I input, PlaceInfo place);

  /// Do what the plan said.
  Future<O> write(I input, PlaceInfo place);
}

/// Whether one strategy fits a place, and what it lacks if not.
final class Availability {
  const Availability(this.strategy, {this.missing = const {}, this.note});

  final String strategy;
  final Set<String> missing;

  /// Why it is unavailable beyond missing facts, if anything.
  final String? note;

  bool get ok => missing.isEmpty && note == null;

  String get reason => ok
      ? 'available'
      : [
          if (missing.isNotEmpty) 'missing ${missing.join(', ')}',
          ?note,
        ].join('; ');
}

/// Which strategy was chosen for a place, and what was passed over.
final class Selection<S extends Strategy<Object?, Object?>> {
  Selection(Iterable<S> strategies, Facts facts)
    : considered = [for (final s in strategies) (s, s.available(facts))];

  /// Every strategy in preference order, with its availability.
  final List<(S, Availability)> considered;

  S? get chosen {
    for (final (s, a) in considered) {
      if (a.ok) return s;
    }
    return null;
  }

  /// One line for logs: what was skipped and why, and what was chosen.
  String get why {
    final parts = <String>[];
    for (final (s, a) in considered) {
      if (a.ok) return (parts..add('${s.name} chosen')).join('; ');
      parts.add('${s.name} skipped (${a.reason})');
    }
    return 'nothing fits: ${parts.join('; ')}';
  }
}
