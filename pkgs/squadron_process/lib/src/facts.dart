import 'package:meta/meta.dart';

/// Keys of the facts a place reports. Additions are agreed in the contracts
/// table (p0g-stack reshape summary) before they land here.
abstract final class Fact {
  /// The place runs with root (effective uid 0).
  static const root = 'root';

  /// The place can open block devices (partitions) for reading.
  static const blockDevices = 'block_devices';

  /// The place can reach USB devices through the OS (`/dev/bus/usb`).
  static const usbNative = 'usb.native';

  /// The place can reach USB devices through WebUSB (`navigator.usb`).
  static const usbWeb = 'usb.web';

  /// The place can start other processes.
  static const processSpawn = 'process.spawn';

  /// The place has storage that survives a restart of the place.
  static const fsPersistent = 'fs.persistent';

  /// The place has a network interface other than loopback that is up.
  static const net = 'net';

  static const all = [
    root,
    blockDevices,
    usbNative,
    usbWeb,
    processSpawn,
    fsPersistent,
    net,
  ];
}

/// What a place can do, as checked by the place itself.
///
/// Facts come from the place, never from the platform: a WebUI page and the
/// root process it started run on the same phone and report different facts.
/// A key that is absent means "not checked", which reads as false.
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
