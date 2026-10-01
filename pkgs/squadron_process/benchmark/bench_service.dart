import 'dart:typed_data';

import 'package:squadron/squadron.dart';

import 'src/entry.dart';

/// The service every place runs: a no-op call for latency, and two streams
/// for throughput (large byte chunks, and many small items).
class BenchService implements WorkerService {
  static const pingCmd = 1;
  static const bytesCmd = 2;
  static const itemsCmd = 3;

  @override
  late final OperationsMap operations = OperationsMap({
    pingCmd: (req) => req.args[0],
    bytesCmd: (req) => _bytes(req.args[0] as int, req.args[1] as int),
    itemsCmd: (req) =>
        Stream.fromIterable(Iterable<int>.generate(req.args[0] as int)),
  });

  Stream<Uint8List> _bytes(int chunks, int size) async* {
    final chunk = Uint8List(size);
    for (var i = 0; i < size; i++) {
      chunk[i] = i;
    }
    for (var i = 0; i < chunks; i++) {
      yield chunk;
    }
  }
}

/// Hand-written client proxy (what squadron_builder generates).
class BenchWorker extends Worker {
  BenchWorker() : super(benchEntryPoint);

  @override
  List? getStartArgs() => null;

  Future<dynamic> ping(int n) => send(BenchService.pingCmd, args: [n]);

  Stream<dynamic> bytes(int chunks, int size) =>
      stream(BenchService.bytesCmd, args: [chunks, size]);

  Stream<dynamic> items(int count) =>
      stream(BenchService.itemsCmd, args: [count]);
}
