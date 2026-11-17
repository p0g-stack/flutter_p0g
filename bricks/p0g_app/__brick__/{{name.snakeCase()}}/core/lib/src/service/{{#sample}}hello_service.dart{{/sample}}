import 'dart:async';

import 'package:logging/logging.dart';
import 'package:squadron/squadron.dart';

import '../facts/facts.dart';
import '../log.dart';
{{#rust}}import '../strategy/digest.dart';
{{/rust}}import 'hello_service.activator.g.dart';

part 'hello_service.worker.g.dart';

/// An example Squadron service. The same class runs in every place: an
/// isolate, a Web Worker, or the CLI's `serve` mode in another process.
///
/// Add more with `mason make service`.
@SquadronService(
  baseUrl: '~/workers',
  targetPlatform: TargetPlatform.vm | TargetPlatform.web,
)
base class HelloService {
  static final _log = Logger('service.hello');

  /// Runs where the service runs: its logs reach the caller's sink.
  HelloService() {
    forwardLogs();
  }

  @squadronMethod
  FutureOr<String> hello(String who) {
    _log.fine('hello $who');
    return 'Hello, $who!';
  }

  /// Streams work the same in every place.
  @squadronMethod
  Stream<int> count(int to) async* {
    for (var i = 1; i <= to; i++) {
      yield i;
    }
  }

  /// The facts of the place this service is running in, as it checks them.
  @squadronMethod
  Future<Map<String, Object?>> facts() async =>
      (await PlaceInfo.current()).facts.toMap();
{{#rust}}
  /// SHA-256 of [text] by the `digest` objective in this place: `strategy`
  /// says whether Rust or Dart computed `sha256`.
  @squadronMethod
  Future<Map<String, String>> sha256(String text) async {
    final place = await PlaceInfo.current();
    final strategy = digest.selectRead(place).chosen?.name ?? 'none';
    return {'sha256': await digest.run(text, place), 'strategy': strategy};
  }
{{/rust}}}
