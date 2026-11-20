import 'dart:async';

import 'package:squadron/squadron.dart';

import '../bench_service.dart';

/// One place's numbers.
class BenchResult {
  BenchResult(
    this.runtime,
    this.place,
    this.callUs,
    this.mibPerS,
    this.itemsPerS,
  );

  final String runtime, place;

  /// Mean round trip of one sequential call, in microseconds.
  final double callUs;

  /// Stream throughput of 64 KiB chunks.
  final double mibPerS;

  /// Stream throughput of small items (ints).
  final double itemsPerS;

  Map<String, Object> toJson() => {
    'runtime': runtime,
    'place': place,
    'call_us': callUs,
    'mib_per_s': mibPerS,
    'items_per_s': itemsPerS,
  };

  static BenchResult fromJson(Map m) => BenchResult(
    m['runtime'] as String,
    m['place'] as String,
    (m['call_us'] as num).toDouble(),
    (m['mib_per_s'] as num).toDouble(),
    (m['items_per_s'] as num).toDouble(),
  );

  String row() =>
      '| $runtime | $place | ${callUs.toStringAsFixed(1)} | '
      '${mibPerS.toStringAsFixed(0)} | ${_k(itemsPerS)} |';

  static String _k(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0);

  static const header =
      '| Runtime | Place | Call (µs, mean) | 64 KiB stream (MiB/s) '
      '| Small items (/s) |\n|---|---|---:|---:|---:|';
}

const calls = 2000;
const chunkSize = 64 * 1024;
const chunks = 512; // 32 MiB
const items = 50000;
const rounds = 5;

/// Runs the three measurements against [worker] and returns the median of
/// [rounds] rounds for each, after one warm-up round.
Future<BenchResult> measure(
  String runtime,
  String place,
  BenchWorker worker,
) async {
  final callRuns = <double>[], mibRuns = <double>[], itemRuns = <double>[];
  for (var r = 0; r <= rounds; r++) {
    final warm = r == 0;

    var sw = Stopwatch()..start();
    for (var i = 0; i < calls; i++) {
      await worker.ping(i);
    }
    sw.stop();
    if (!warm) callRuns.add(sw.elapsedMicroseconds / calls);

    sw = Stopwatch()..start();
    var bytes = 0;
    await for (final chunk in worker.bytes(chunks, chunkSize)) {
      bytes += (chunk as List).length;
    }
    sw.stop();
    if (bytes != chunks * chunkSize) {
      throw StateError('$place: got $bytes bytes');
    }
    if (!warm) {
      mibRuns.add(bytes / (1024 * 1024) / (sw.elapsedMicroseconds / 1e6));
    }

    sw = Stopwatch()..start();
    var n = 0;
    await for (final _ in worker.items(items)) {
      n++;
    }
    sw.stop();
    if (n != items) throw StateError('$place: got $n items');
    if (!warm) itemRuns.add(n / (sw.elapsedMicroseconds / 1e6));
  }
  return BenchResult(
    runtime,
    place,
    _median(callRuns),
    _median(mibRuns),
    _median(itemRuns),
  );
}

double _median(List<double> v) => (v..sort())[v.length ~/ 2];

/// Starts [worker] and checks it answers before timing anything.
Future<void> ready(Worker worker) async {
  await (worker as BenchWorker).ping(0);
}
