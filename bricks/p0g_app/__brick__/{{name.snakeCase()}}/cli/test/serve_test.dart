@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  test(
    'the hello service runs in the CLI as a process place',
    () async {
      final dir = await Directory.systemTemp.createTemp('p0g');
      addTearDown(() => dir.delete(recursive: true));
      final session = '${dir.path}/hello.place.json';
      final place = ProcessPlace(
        launcher: const IoProcessLauncher(),
        store: FileEndpointStore(session),
        command: ProcessCommand(
          Platform.resolvedExecutable,
          arguments: [
            'run',
            'bin/{{name.snakeCase()}}.dart',
            'serve',
            'hello',
            '--session-file',
            session,
            '--grace-ms',
            '200',
          ],
        ),
        readyTimeout: const Duration(minutes: 2),
      );

      final worker = place.bind(HelloServiceWorker());
      addTearDown(worker.terminate);
      expect(await worker.hello('process'), 'Hello, process!');
      expect(await worker.count(3).toList(), [1, 2, 3]);
      expect((await place.facts())[Fact.processSpawn], isA<bool>());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
