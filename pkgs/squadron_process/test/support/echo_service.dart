import 'dart:async';

import 'package:cancelation_token/cancelation_token.dart';
import 'package:squadron/squadron.dart';

/// A hand-written Squadron service (what squadron_builder would generate),
/// used to check that a real service runs unchanged in every place.
class EchoService implements WorkerService {
  static const echoCmd = 1;
  static const countCmd = 2;
  static const failCmd = 3;
  static const waitCmd = 4;
  static const bytesCmd = 5;

  @override
  late final OperationsMap operations = OperationsMap({
    echoCmd: (req) => req.args[0],
    countCmd: (req) => _count(req.args[0] as int, req.args[1] as int),
    failCmd: (req) => throw WorkerException('failed: ${req.args[0]}'),
    waitCmd: (req) => _wait(req.cancelToken, req.args[0] as int),
    bytesCmd: (req) => (req.args[0] as List).length,
  });

  Stream<int> _count(int n, int delayMs) async* {
    for (var i = 0; i < n; i++) {
      if (delayMs > 0) await Future.delayed(Duration(milliseconds: delayMs));
      yield i;
    }
  }

  Future<String> _wait(CancelationToken? token, int ms) async {
    final done = Future.delayed(Duration(milliseconds: ms), () => 'finished');
    if (token == null) return done;
    await Future.any([done, token.onCanceled]);
    token.throwIfCanceled();
    return done;
  }
}

void echoEntryPoint(WorkerRequest command) =>
    run((_) => EchoService(), command);

/// The client-side proxy, as generated code would write it.
class EchoWorker extends Worker {
  EchoWorker() : super(echoEntryPoint);

  @override
  List? getStartArgs() => null;

  Future<dynamic> echo(Object? value) =>
      send(EchoService.echoCmd, args: [value]);

  Stream<dynamic> count(int n, {int delayMs = 0}) =>
      stream(EchoService.countCmd, args: [n, delayMs]);

  Future<dynamic> fail(String why) => send(EchoService.failCmd, args: [why]);

  Future<dynamic> wait(int ms, {CancelationToken? token}) =>
      send(EchoService.waitCmd, args: [ms], token: token);
}
