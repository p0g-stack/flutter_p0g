@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  test('the hello service runs in the CLI as a process place', () async {
    final dir = await Directory.systemTemp.createTemp('p0g');
    addTearDown(() => dir.delete(recursive: true));
    final session = '${dir.path}/place.json';
    final place = ProcessPlace(
      launcher: const IoProcessLauncher(),
      store: FileEndpointStore(session),
      command: ProcessCommand(
        Platform.resolvedExecutable,
        arguments: [
          'run',
          'bin/{{name.snakeCase()}}.dart',
          'serve',
          '--session-file',
          session,
          '--grace-ms',
          '200',
        ],
      ),
      readyTimeout: const Duration(minutes: 2),
    );

    final worker = place.bind(HelloServiceWorker(), service: 'hello');
    addTearDown(worker.terminate);
    expect(await worker.hello('process'), 'Hello, process!');
    expect(await worker.count(3).toList(), [1, 2, 3]);
    expect((await place.facts())[Fact.processSpawn], isA<bool>());
{{#rust}}    // The serve process loads rust/target's library for itself.
    expect((await worker.sha256('abc'))['strategy'], 'rust_sha2');
{{/rust}}  }, timeout: const Timeout(Duration(minutes: 3)));
}
