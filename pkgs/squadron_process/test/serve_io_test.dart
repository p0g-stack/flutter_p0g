@TestOn('vm')
library;

import 'dart:io';

import 'package:logger/logger.dart';
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';

void main() {
  group('ServeOptions.parse', () {
    test('defaults and token from the environment only', () {
      final o = ServeOptions.parse(
        [],
        environment: {'SQUADRON_PROCESS_TOKEN': 'from-env'},
      );
      expect(o.port, 0);
      expect(o.token, 'from-env');
      expect(o.sessionFile, isNull);
    });

    test('options in both spellings', () {
      final o = ServeOptions.parse([
        '--port',
        '5000',
        '--session-file=/x/s.json',
        '--grace-ms=250',
      ], environment: const {});
      expect(o.port, 5000);
      expect(o.sessionFile, '/x/s.json');
      expect(o.grace, const Duration(milliseconds: 250));
      expect(o.token, isNull);
    });

    test('rejects unknown options, including a token on argv', () {
      expect(
        () => ServeOptions.parse(['--token=x'], environment: const {}),
        throwsFormatException,
      );
      expect(
        () => ServeOptions.parse(['--port'], environment: const {}),
        throwsFormatException,
      );
    });
  });

  test(
    'serves over a loopback WebSocket and publishes a session file',
    () async {
      final dir = await Directory.systemTemp.createTemp('sp_test_');
      final session = '${dir.path}/run/demo.json';
      final service = EchoWorker();
      final served = await startServe(
        {'echo': service},
        options: ServeOptions(
          sessionFile: session,
          grace: const Duration(milliseconds: 200),
        ),
        facts: () async => {'test.extra': true, 'pid': pid},
      );

      final stored = await FileEndpointStore(session).read();
      expect(stored!.port, served.endpoint.port);
      expect(stored.token, served.endpoint.token);
      expect(served.endpoint.token.length, greaterThanOrEqualTo(32));

      final place = ProcessPlace(store: FileEndpointStore(session));
      final w = place.bind(EchoWorker());
      expect(await w.echo('over ws'), 'over ws');
      expect(await w.count(3).toList(), [0, 1, 2]);
      final facts = await place.facts();
      expect(facts.has('test.extra'), isTrue);
      expect(facts['pid'], pid);

      // Not a WebSocket upgrade on the right path: 404.
      final http = HttpClient();
      final res = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:${served.endpoint.port}/other'),
      )).close();
      expect(res.statusCode, 404);
      http.close();

      // Closing the last link starts the grace window; the host then exits
      // and removes its session file.
      w.stop();
      await served.done.timeout(const Duration(seconds: 5));
      expect(File(session).existsSync(), isFalse);
      service.stop();
      await dir.delete(recursive: true);
    },
  );

  test('a real CLI process hosts the service end to end', () async {
    final dir = await Directory.systemTemp.createTemp('sp_cli_');
    final session = '${dir.path}/demo.json';
    final place = ProcessPlace(
      launcher: const IoProcessLauncher(),
      command: ProcessCommand(
        Platform.resolvedExecutable,
        arguments: [
          'run',
          'test/support/serve_main.dart',
          'serve',
          '--session-file',
          session,
          '--grace-ms',
          '300',
        ],
      ),
      store: FileEndpointStore(session),
      readyTimeout: const Duration(seconds: 120),
    );

    final logs = <String>[];
    final w = place.bind(
      EchoWorker()..channelLogger = _Collect((m) => logs.add('$m')),
    );
    expect(await w.echo('from another process'), 'from another process');
    // A record logged in the host process's service isolate reaches us.
    await w.log('logged in the host');
    await Future.delayed(const Duration(milliseconds: 100));
    expect(logs, contains('logged in the host'));
    expect(await w.count(5).toList(), [0, 1, 2, 3, 4]);
    await expectLater(w.fail('remote'), throwsA(isA<WorkerException>()));
    final facts = await place.facts();
    expect(facts.has('test.cli'), isTrue);
    // It really is another process.
    expect(place.endpoint!.pid, isNot(equals(pid)));

    // Page closed: the process exits after its grace window.
    w.stop();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (File(session).existsSync() && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    expect(
      File(session).existsSync(),
      isFalse,
      reason: 'host should exit and remove its session file',
    );
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _Collect extends Logger {
  _Collect(this._add) : super(output: MemoryOutput());
  final void Function(Object?) _add;

  @override
  void log(
    Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => _add(message);
}
