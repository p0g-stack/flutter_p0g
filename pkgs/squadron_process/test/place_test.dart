@TestOn('vm')
library;

import 'dart:async';

import 'package:squadron/squadron.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';
import 'support/fakes.dart';

void main() {
  late FakeLauncher launcher;
  late FakeStore store;
  const command = ProcessCommand('/opt/demo/bin/demo');

  setUp(() {
    launcher = FakeLauncher();
    store = FakeStore();
  });
  tearDown(() => launcher.dispose());

  ProcessPlace place({Duration? readyTimeout}) => ProcessPlace(
    launcher: launcher,
    command: command,
    store: store,
    connector: launcher.connect,
    readyTimeout: readyTimeout ?? const Duration(seconds: 5),
  );

  test('starts the host from the ready line when none is running', () async {
    final p = place();
    final w = p.bind(EchoWorker());
    expect(await w.echo(42), 42);
    expect(launcher.commands.single.arguments, [
      'serve',
      '--launch-id',
      launcher.endpoints.single.launchId,
    ]);
    expect(p.endpoint!.port, 4000);
    expect((await p.facts())['port'], 4000);
    w.stop();
  });

  test('workers share one host', () async {
    final p = place();
    final a = p.bind(EchoWorker()), b = p.bind(EchoWorker());
    await Future.wait([a.echo(1), b.echo(2)]);
    expect(launcher.commands, hasLength(1));
    expect(launcher.hosts[4000]!.links, 2);
    a.stop();
    b.stop();
  });

  test(
    'reattaches to a running host found in the store (page reload)',
    () async {
      final first = place();
      final w1 = first.bind(EchoWorker());
      await w1.echo('a');
      store.endpoint = first.endpoint;
      w1.stop();

      final reloaded = place();
      final w2 = reloaded.bind(EchoWorker());
      expect(await w2.echo('b'), 'b');
      expect(launcher.commands, hasLength(1));
      w2.stop();
    },
  );

  test('a stale store entry starts a new host', () async {
    store.endpoint = const ProcessEndpoint(port: 9, token: 'gone');
    final p = place();
    final w = p.bind(EchoWorker());
    expect(await w.echo('x'), 'x');
    expect(p.endpoint!.port, 4000);
    w.stop();
  });

  test('a host that never reports ready fails the worker start', () async {
    launcher.silent = true;
    final w = place(readyTimeout: const Duration(milliseconds: 100))
        .bind(EchoWorker());
    await expectLater(
      w.echo(1),
      throwsA(
        isA<WorkerException>().having(
          (e) => e.message,
          'message',
          contains('ready'),
        ),
      ),
    );
    w.stop();
  });

  test('LocalPlace leaves the worker on Squadron\'s own channel', () async {
    final w = const LocalPlace().bind(place().bind(EchoWorker()));
    expect(w.channelFactory, isNull);
    expect(await w.echo('local'), 'local');
    expect(launcher.commands, isEmpty);
    w.stop();
  });

  test(
    'without stdout (an elevation prompt) the host is found in the store',
    () async {
      launcher.stdoutVisible = false;
      // An older host's entry is still there; it must not be taken.
      store.endpoint = const ProcessEndpoint(
        port: 9,
        token: 'old',
        launchId: 'older',
      );
      final p = ProcessPlace(
        launcher: launcher,
        command: command,
        store: store,
        connector: launcher.connect,
        storePollInterval: const Duration(milliseconds: 20),
      );
      final w = p.bind(EchoWorker());
      // The stale entry fails to connect, so the place launches; the new host
      // publishes its endpoint shortly after.
      Timer(
        const Duration(milliseconds: 100),
        () => store.endpoint = launcher.endpoints.last,
      );
      expect(await w.echo('elevated'), 'elevated');
      expect(p.endpoint!.launchId, launcher.endpoints.last.launchId);
      w.stop();
    },
  );

  test('ready lines parse; anything else is ignored', () {
    final e = ProcessEndpoint(port: 1234, token: 'abc', pid: 7, launchId: 'L');
    final parsed = ProcessEndpoint.tryParse(e.encode())!;
    expect(parsed.launchId, 'L');
    expect(parsed.port, 1234);
    expect(parsed.token, 'abc');
    expect(parsed.pid, 7);
    expect(parsed.uri.toString(), 'ws://127.0.0.1:1234/squadron');
    expect(ProcessEndpoint.tryParse('hello'), isNull);
    // Hostnames are refused: endpoints are IP literals.
    expect(
      ProcessEndpoint.tryParse(
        '{"squadron_process":1,"host":"localhost","port":1,"token":"a"}',
      ),
      isNull,
    );
    expect(
      ProcessEndpoint.tryParse(
        '{"squadron_process":1,"host":"::1","port":1,"token":"a"}',
      )!.uri.host,
      '::1',
    );
    expect(ProcessEndpoint.tryParse('{"port":1,"token":"a"}'), isNull);
    expect(ProcessEndpoint.tryParse('{"squadron_process":1,"port":1}'), isNull);
  });
}
