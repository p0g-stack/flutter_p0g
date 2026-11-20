import 'package:squadron/squadron.dart';

import '../bench_service.dart';

/// Web Worker entry point, compiled to bench_worker.dart.js.
void main() => run((_) => BenchService());
