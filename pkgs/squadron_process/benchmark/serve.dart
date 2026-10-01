import 'dart:io';

import 'package:squadron_process/io.dart';

import 'bench_service.dart';

/// The process place host: an app CLI's `serve` mode in miniature. The
/// service runs in an isolate inside this process, as a generated worker
/// would.
Future<void> main(List<String> args) async {
  exit(await serve({'bench': BenchWorker()}, args));
}
