import 'package:squadron/squadron.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';
{{#process_place}}import 'package:squadron_process/squadron_process.dart';
{{/process_place}}
/// A generated worker constructor, such as `HelloServiceWorker.new`.
typedef WorkerConstructor<W extends Worker> =
    W Function({
      PlatformThreadHook? threadHook,
      ExceptionManager? exceptionManager,
    });

/// The place the app's services run in, and how to start a worker there.
abstract interface class PlaceLink {
  Place get place;

  /// Start the worker for [service] in this place.
  Future<W> start<W extends Worker>(
    String service,
    WorkerConstructor<W> create,
  );

  Future<void> close();
}

/// Open the place for this run of the app.
Future<PlaceLink> openPlace() async {
{{#process_place}}  const endpoint = String.fromEnvironment('P0G_PROCESS_ENDPOINT');
  if (endpoint.isNotEmpty) {
    return ProcessLink.connect(Uri.parse(endpoint));
  }
{{/process_place}}  return LocalLink();
}

/// Squadron's own place: an isolate on native, a Web Worker on the web.
///
/// It reports no facts, because it has checked none; strategies that need
/// root or devices are unavailable here, which is the honest answer.
final class LocalLink implements PlaceLink {
  final _workers = <Worker>[];

  @override
  final Place place = Place(
    Squadron.platformType.isVm ? 'isolate' : 'web_worker',
  );

  @override
  Future<W> start<W extends Worker>(
    String service,
    WorkerConstructor<W> create,
  ) async {
    final worker = create();
    await worker.start();
    _workers.add(worker);
    return worker;
  }

  @override
  Future<void> close() async {
    for (final w in _workers) {
      w.terminate();
    }
  }
}
{{#process_place}}
/// The app's own CLI in serve mode, in another (on WebUI, root) process.
final class ProcessLink implements PlaceLink {
  ProcessLink._(this._place, this.place);

  static Future<ProcessLink> connect(Uri endpoint) async {
    final p = await ProcessPlace.connect(endpoint);
    return ProcessLink._(p, Place('process', Facts(p.facts)));
  }

  final ProcessPlace _place;

  @override
  final Place place;

  @override
  Future<W> start<W extends Worker>(
    String service,
    WorkerConstructor<W> create,
  ) => _place.start(service, create);

  @override
  Future<void> close() => _place.close();
}
{{/process_place}}
