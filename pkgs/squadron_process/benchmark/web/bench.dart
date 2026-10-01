// Benchmarks the Web Worker place and the process place in a browser.
// Compiled to bench.dart.js and loaded by index.html; run_web.dart serves
// it, starts the process place host, and collects the results.
import 'dart:convert';
import 'dart:js_interop';

import 'package:squadron_process/squadron_process.dart';
import 'package:web/web.dart' as web;

import '../bench_service.dart';
import '../src/measure.dart';

Future<void> main() async {
  final q = Uri.base.queryParameters;
  final runtime = q['runtime'] ?? 'Chromium';
  final out = <Object>[];
  try {
    final worker = const LocalPlace().bind(BenchWorker());
    await ready(worker);
    out.add((await measure(runtime, 'web_worker', worker)).toJson());
    worker.stop();

    final place = ProcessPlace(
      endpoint: ProcessEndpoint(
        port: int.parse(q['port']!),
        token: q['token']!,
      ),
    );
    final process = place.bind(BenchWorker(), service: 'bench');
    await ready(process);
    out.add((await measure(runtime, 'process', process)).toJson());
    process.stop();
  } catch (e, st) {
    out.add({'error': '$e\n$st'});
  }
  await web.window
      .fetch(
        '/results'.toJS,
        web.RequestInit(method: 'POST', body: jsonEncode(out).toJS),
      )
      .toDart;
}
