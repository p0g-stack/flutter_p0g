import 'package:squadron/squadron.dart';

import '../bench_service.dart';

/// Isolate entry point on the Dart VM.
void benchEntryPoint(WorkerRequest command) =>
    run((_) => BenchService(), command);
