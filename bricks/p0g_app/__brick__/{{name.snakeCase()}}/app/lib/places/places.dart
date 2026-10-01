import 'package:squadron_process/squadron_process.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

import 'launch.dart';

/// The places this run of the app can put a service in.
///
/// Squadron's own place (an isolate, or a Web Worker on the web) is always
/// there. The process place, this app's CLI in `serve` mode hosting every
/// service, is there when this platform can launch it: flutter-webui's root
/// channel on WebUI, `IoProcessLauncher` on a desktop (with `P0G_CLI` naming
/// the CLI). Choosing a launcher by platform is fine; what a place can do
/// comes from its facts.
final class Places {
  Places({ProcessPlace? Function() process = openProcessPlace})
    : process = process();

  final Place local = localPlace;

  /// The process place, or null where this platform cannot launch one.
  final ProcessPlace? process;

  /// The place of [kind] (`PlaceKind.process`, else the local one).
  Place forKind(String kind) =>
      (kind == PlaceKind.process ? process : null) ?? local;

  /// Where work that must keep going runs: the process place when there is
  /// one. A Web Worker lives in the page, and on WebUI the page stops: WebUI X
  /// pauses its timers while hidden, and Next and WebUI X recreate it on
  /// rotation. See docs/patterns/places.md in bricks.
  Place get lasting => process ?? local;
}
