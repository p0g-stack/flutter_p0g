import 'package:meta/meta.dart';

/// Checks the facts of the place it runs in.
typedef FactsCheck = Future<Map<String, Object?>> Function();

/// What a place can do, as checked by the place itself.
///
/// A neutral map: squadron_process defines no keys and makes no checks. The
/// app supplies a [FactsCheck] to each place; the process place runs it in the
/// host process and sends the result in the handshake, so a client and the
/// process it started (say, an unprivileged UI and an elevated helper) report
/// what each of them can really do. A key that is absent reads as false.
@immutable
class PlaceFacts {
  PlaceFacts(Map<String, Object?> values) : _values = Map.unmodifiable(values);

  const PlaceFacts.none() : _values = const {};

  final Map<String, Object?> _values;

  /// Whether [fact] was checked and holds.
  bool has(String fact) => _values[fact] == true;

  /// The raw value for [fact], for facts that carry more than a flag.
  Object? operator [](String fact) => _values[fact];

  Iterable<String> get keys => _values.keys;

  /// Facts with [other] overriding this, for a place that adds its own checks.
  PlaceFacts merge(Map<String, Object?> other) =>
      PlaceFacts({..._values, ...other});

  Map<String, Object?> toMap() => _values;

  static PlaceFacts fromMap(Map map) =>
      PlaceFacts({for (final e in map.entries) '${e.key}': e.value});

  @override
  bool operator ==(Object other) =>
      other is PlaceFacts &&
      other._values.length == _values.length &&
      _values.entries.every((e) => other._values[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'PlaceFacts($_values)';
}
