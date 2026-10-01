import 'package:squadron_process/squadron_process.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

import 'launch.dart';

/// The places this run of the app can put a service in.
///
/// Squadron's own place (an isolate, or a Web Worker on the web) is always
/// there. The process place, the app's CLI in `serve` mode, is there when
/// this platform has a launcher for it: `IoProcessLauncher` on a desktop
/// (set `P0G_CLI` to the CLI executable), flutter-webui's root channel on
/// WebUI. A process place hosts one service, so there is one per service.
final class Places {
  Places({ProcessPlace? Function(String service)? process})
    : _process = process ?? processPlaceFor;

  final ProcessPlace? Function(String service) _process;
  final _byService = <String, ProcessPlace?>{};

  final Place local = localPlace;

  /// Whether this platform can launch the process place at all.
  bool get hasProcess => _process('') != null;

  /// The process place for [service], or null where there is none.
  ProcessPlace? process(String service) =>
      _byService.putIfAbsent(service, () => _process(service));

  /// The place of [kind] (`PlaceKind.process`, else the local one) for
  /// [service].
  Place forService(String kind, String service) =>
      (kind == PlaceKind.process ? process(service) : null) ?? local;
}
