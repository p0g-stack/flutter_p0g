// A Squadron service served by one process and used by another.
//
// For brevity this example hosts the service in the same process
// (startServe) and connects to it over the loopback WebSocket, exactly as a
// separate client would. In an app, the host side is your CLI's `serve`
// subcommand and the client starts it through a ProcessLauncher; see
// doc/serve.md and doc/launchers.md.
//
// The worker below is written by hand so the example runs without
// code generation; squadron_builder generates the same shape.
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';

class GreeterService implements WorkerService {
  static const greetCmd = 1;
  static const countCmd = 2;

  @override
  late final OperationsMap operations = OperationsMap({
    greetCmd: (req) => 'Hello, ${req.args[0]}!',
    countCmd: (req) =>
        Stream.fromIterable(List.generate(req.args[0] as int, (i) => i + 1)),
  });
}

void greeterEntryPoint(WorkerRequest command) =>
    run((_) => GreeterService(), command);

class GreeterWorker extends Worker {
  GreeterWorker() : super(greeterEntryPoint);

  @override
  List? getStartArgs() => null;

  Future<String> greet(String name) async =>
      await send(GreeterService.greetCmd, args: [name]) as String;

  Stream<int> count(int n) =>
      stream(GreeterService.countCmd, args: [n]).cast<int>();
}

Future<void> main() async {
  // Host side: what `my_app serve` does, minus printing and exiting.
  final hosted = GreeterWorker();
  final served = await startServe({
    'greeter': hosted,
  }, facts: () async => {'example': true});

  // Client side: bind a worker to the process place and use it as usual.
  final place = ProcessPlace(endpoint: served.endpoint);
  final greeter = place.bind(GreeterWorker(), service: 'greeter');

  print(await greeter.greet('process place'));
  print(await greeter.count(3).toList());
  print(await place.facts());

  greeter.stop();
  await served.close();
  hosted.stop();
}
