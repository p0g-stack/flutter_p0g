/// What a place has checked it can do.
///
/// Facts come from the place a service runs in (an isolate, a Web Worker, the
/// app's CLI as a root process), never from `kIsWeb` or `Platform`: WebUI
/// reports web, AERA reports Linux, and neither says whether this place has
/// root. A missing key means "not checked", which strategies treat as "no".
extension type const Facts(Map<String, Object?> _values) {
  /// No facts: nothing was checked.
  static const Facts none = Facts(<String, Object?>{});

  /// Whether [key] was checked and is `true`.
  bool has(String key) => _values[key] == true;

  /// The raw value for [key], or null when it was not checked.
  Object? operator [](String key) => _values[key];

  /// The keys that are `true`, sorted, for logs.
  List<String> get present => [
    for (final e in _values.entries)
      if (e.value == true) e.key,
  ]..sort();

  Map<String, Object?> toJson() => Map.unmodifiable(_values);
}

/// Fact keys. squadron_process owns this list; new keys land there first.
abstract final class Fact {
  /// The place runs as root (uid 0).
  static const root = 'root';

  /// The place can open block devices (`/dev/block/...`).
  static const blockDevices = 'block_devices';

  /// The place can use USB through the OS (usbfs / libusb).
  static const usbNative = 'usb.native';

  /// The place can use USB through WebUSB.
  static const usbWeb = 'usb.web';

  /// The place can start processes.
  static const processSpawn = 'process.spawn';

  /// Files written by the place survive a restart.
  static const fsPersistent = 'fs.persistent';

  /// The place has network access.
  static const net = 'net';
}
