import 'package:squadron_process/squadron_process.dart';

import 'check.dart';

export 'package:squadron_process/squadron_process.dart' show PlaceFacts;

export 'check.dart' show checkFacts;

/// The facts vocabulary. squadron_process carries facts as a neutral map;
/// these keys and their checks (`check_io.dart`, `check_web.dart`) are ours.
/// A new key lands here with the check that decides it.
abstract final class Fact {
  /// The place runs with root (effective uid 0).
  static const root = 'root';

  /// The place can open a kernel-listed block device for reading.
  static const blockDevices = 'block_devices';

  /// The place can reach USB devices through the OS (`/dev/bus/usb`).
  static const usbNative = 'usb.native';

  /// The place can reach USB devices through WebUSB (`navigator.usb`).
  static const usbWeb = 'usb.web';

  /// The place can start other processes.
  static const processSpawn = 'process.spawn';

  /// Files the place writes survive a restart. Natively: its working folder
  /// is writable (the WebUI process place works in `/data/adb/<id>`). In a
  /// page or Web Worker: the browser granted persistent storage
  /// (`navigator.storage.persisted()`), which manager WebViews never do, so
  /// on WebUI persistent files belong to the process place.
  static const fsPersistent = 'fs.persistent';

  /// The place has a network interface other than loopback that is up.
  static const net = 'net';
{{#rust}}
  /// The app's Rust library (`rust/`) is loaded in this place.
  static const native = 'native';
{{/rust}}

  static const all = [
    root,
    blockDevices,
    usbNative,
    usbWeb,
    processSpawn,
    fsPersistent,
    net,
{{#rust}}    native,
{{/rust}}  ];
}

/// What a place has checked it can do.
///
/// Facts come from the place a service runs in (an isolate, a Web Worker, the
/// app's CLI as a root process), never from `kIsWeb` or `Platform`: WebUI
/// reports web, AERA reports Linux, and neither says whether this place has
/// root. A missing key means "not checked", which reads as "no".
typedef Facts = PlaceFacts;

extension FactsReading on PlaceFacts {
  /// The facts that hold, sorted, for logs.
  List<String> get present => [
    for (final k in keys)
      if (has(k)) k,
  ]..sort();

  /// The facts from [needed] that do not hold here.
  Set<String> missing(Iterable<String> needed) => {
    for (final f in needed)
      if (!has(f)) f,
  };
}

/// Squadron's own place for this platform, checking our facts.
const LocalPlace localPlace = LocalPlace(check: checkFacts);

/// Where code is running, and what it checked it can do there.
final class PlaceInfo {
  const PlaceInfo(this.kind, this.facts);

  /// `isolate`, `web_worker`, `process` or `cli`.
  final String kind;
  final Facts facts;

  /// The place this code runs in, with facts checked here and now. Inside a
  /// service hosted by the CLI's `serve`, these are the root process's facts.
  static Future<PlaceInfo> current() async =>
      PlaceInfo(localPlace.kind, await localPlace.facts());

  @override
  String toString() => kind;
}
