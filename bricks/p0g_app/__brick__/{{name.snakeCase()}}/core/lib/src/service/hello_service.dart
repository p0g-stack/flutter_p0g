import 'dart:async';

import 'package:logging/logging.dart';
import 'package:squadron/squadron.dart';

import '../facts/facts.dart';
import 'hello_service.activator.g.dart';

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
}
