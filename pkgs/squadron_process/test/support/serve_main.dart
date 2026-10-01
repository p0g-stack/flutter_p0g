import 'dart:io';

import 'package:squadron_process/io.dart';

import 'echo_service.dart';

/// An app CLI in miniature: `serve` hosts the echo service in an isolate and
/// serves it as a process place.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'serve') {
    exit(
      await serve(
        EchoWorker(),
        args.skip(1).toList(),
        extraFacts: {'test.cli': true},
      ),
    );
  }
  stderr.writeln('usage: serve_main serve [options]');
  exit(64);
}
