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
///
/// A write to a device outside this place (a phone on USB, reached from the
/// CLI or the page) names that device in its input, such as its serial and
/// mode, shows it in [plan]'s steps, and [write] refuses when the device
/// connected now is not that one. Otherwise a cable swapped after the user
/// confirmed writes to the other phone. A write to this device (`dd` in the
/// root process) has nothing to pin. See docs/patterns/devices.md in bricks.
abstract base class WriteStrategy<I, O> extends Strategy<I, O> {
  const WriteStrategy();

  /// Describe, step by step, what [write] would do. No side effects.
  Future<List<String>> plan(I input, PlaceInfo place);

  /// Do what the plan said.
  Future<O> write(I input, PlaceInfo place);
}

/// Whether one strategy fits a place, and what it lacks if not.
final class Availability {
  const Availability(
    this.strategy, {
    this.missing = const {},
    this.note,
    this.waiting = false,
  }) : assert(!waiting || note != null, 'say what the user should do');

  final String strategy;
  final Set<String> missing;

  /// Why it is unavailable beyond missing facts, if anything.
  final String? note;

  /// It would run once the user acts, as [note] says: connect a phone, put
  /// it in fastbootd. A UI shows these as an action, not as "unavailable".
  /// Missing facts win: a place that can't run it at all doesn't wait.
  final bool waiting;

  bool get ok => missing.isEmpty && note == null;

  /// Not now, but once the user does what [note] says.
  bool get waits => waiting && missing.isEmpty;

  String get reason => ok
      ? 'available'
      : waits
      ? 'waits: $note'
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

  /// The strategies that would run once the user acts (`waiting`), in
  /// order: what a UI offers when nothing, or something worse, was chosen.
  List<(S, Availability)> get waiting => [
    for (final c in considered)
      if (c.$2.waits) c,
  ];

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
      parts.add(
        a.waits ? '${s.name} ${a.reason}'
            : '${s.name} skipped (${a.reason})',
      );
    }
    return 'nothing fits: ${parts.join('; ')}';
  }
}
