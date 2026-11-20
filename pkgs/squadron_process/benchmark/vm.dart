// Benchmarks the isolate place and the process place on the Dart VM.
//
//   dart run benchmark/vm.dart [<serve-executable>]
//
// With no argument the process place host is `dart benchmark/serve.dart`
// (JIT); tool/bench.sh passes an AOT-compiled one, as an app would ship.
import 'dart:io';

import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';

import 'bench_service.dart';
import 'src/measure.dart';

Future<void> main(List<String> args) async {
  final command = args.isNotEmpty
      ? ProcessCommand(args.first, arguments: const ['--grace-ms', '500'])
      : ProcessCommand(
          Platform.resolvedExecutable,
          arguments: [
            Platform.script.resolve('serve.dart').toFilePath(),
            '--grace-ms',
            '500',
          ],
        );
  final runtime = 'VM ${Platform.version.split(' ').first}';

  final results = <BenchResult>[];

  final isolate = const LocalPlace().bind(BenchWorker());
  await ready(isolate);
  results.add(await measure(runtime, 'isolate', isolate));
  isolate.stop();

  final place = ProcessPlace(
    launcher: const IoProcessLauncher(),
    command: command,
  );
  final process = place.bind(BenchWorker(), service: 'bench');
  await ready(process);
  results.add(await measure(runtime, 'process', process));
  process.stop();

  print(BenchResult.header);
  for (final r in results) {
    print(r.row());
  }
  exit(0);
}
