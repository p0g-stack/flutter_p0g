@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cancelation_token/cancelation_token.dart';
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';

const token = 'secret-token';

/// A host serving the echo service (in an isolate), reached over in-memory
/// links: the process place without the process.
class Rig {
  Rig({Duration grace = const Duration(milliseconds: 200)})
    : host = PlaceHost(
        services: {'echo': EchoWorker()},
        token: token,
        grace: grace,
        firstLinkGrace: const Duration(seconds: 5),
        checkFacts: () async => PlaceFacts({'root': true}),
      );

  final PlaceHost host;
  final clientEnds = <PlaceLink>[];

  ProcessPlace get place => ProcessPlace(
    endpoint: const ProcessEndpoint(port: 1, token: token),
    connector: (_) async => link(),
  );

  PlaceLink link() {
    final (client, server) = PlaceLink.pair();
    host.accept(server);
    clientEnds.add(client);
    return client;
  }

  Future<void> dispose() async {
    await host.shutdown('test over');
    (host.services.values.single as Worker).stop();
  }
}

void main() {
  late Rig rig;
  setUp(() => rig = Rig());
  tearDown(() => rig.dispose());

  test('a Squadron worker bound to the place runs its service there', () async {
    final w = rig.place.bind(EchoWorker());
    expect(await w.echo('hi'), 'hi');
    expect(
      await w.echo({
        'a': Uint8List.fromList([1, 2]),
      }),
      {
        'a': [1, 2],
      },
    );
    expect(await w.count(4).toList(), [0, 1, 2, 3]);
    expect(rig.host.links, 1);
    w.stop();
  });

  test('the handshake carries the facts of the host place', () async {
    final place = rig.place;
    expect(await place.facts(), PlaceFacts({'root': true}));
    expect(place.kind, PlaceKind.process);
  });

  test('service exceptions arrive as Squadron exceptions', () async {
    final w = rig.place.bind(EchoWorker());
    await expectLater(
      w.fail('nope'),
      throwsA(
        isA<WorkerException>().having(
          (e) => e.message,
          'message',
          contains('failed: nope'),
        ),
      ),
    );
    w.stop();
  });

  test('values the link cannot carry fail that request only', () async {
    final w = rig.place.bind(EchoWorker());
    await expectLater(w.echo(Object()), throwsA(isA<SquadronException>()));
    expect(await w.echo(1), 1);
    w.stop();
  });

  test('cancelling a token cancels the task in the host', () async {
    final w = rig.place.bind(EchoWorker());
    final t = CancelableToken();
    final call = w.wait(10000, token: t);
    await Future.delayed(const Duration(milliseconds: 100));
    expect(rig.host.running, 1);
    t.cancel();
    await expectLater(call, throwsA(isA<CanceledException>()));
    await _until(() => rig.host.running == 0);
    w.stop();
  });

  test('cancelling a stream subscription stops it in the host', () async {
    final w = rig.place.bind(EchoWorker());
    final got = <dynamic>[];
    final sub = w.count(1000, delayMs: 10).listen(got.add);
    await _until(() => got.length >= 3);
    await sub.cancel();
    await _until(() => rig.host.running == 0);
    final n = got.length;
    await Future.delayed(const Duration(milliseconds: 50));
    expect(got.length, n);
    w.stop();
  });

  test('a wrong token is refused', () async {
    final (client, server) = PlaceLink.pair();
    rig.host.accept(server);
    await expectLater(
      ProcessChannel.connect(client, token: 'wrong'),
      throwsA(
        isA<WorkerException>().having(
          (e) => e.message,
          'message',
          contains('bad token'),
        ),
      ),
    );
    expect(rig.host.links, 0);
  });

  test('a client that never says hello is dropped', () async {
    final host = PlaceHost(
      services: {'echo': EchoWorker()},
      token: token,
      handshakeTimeout: const Duration(milliseconds: 50),
    );
    final (client, server) = PlaceLink.pair();
    host.accept(server);
    final frames = await client.frames.toList();
    expect(frames, hasLength(1)); // the refusal
    await host.shutdown();
    (host.services.values.single as Worker).stop();
  });

  test('losing the link fails pending calls on the client', () async {
    final w = rig.place.bind(EchoWorker());
    final call = w.wait(10000);
    await Future.delayed(const Duration(milliseconds: 50));
    await rig.clientEnds.single.close();
    await expectLater(
      call,
      throwsA(
        isA<WorkerException>().having(
          (e) => e.message,
          'message',
          contains('link is gone'),
        ),
      ),
    );
    w.stop();
  });

  group('one host, several services', () {
    late PlaceHost host;
    var launches = 0;
    setUp(() {
      launches = 0;
      host = PlaceHost(
        services: {'a': EchoWorker(), 'b': EchoWorker()},
        token: token,
      );
    });
    tearDown(() async {
      await host.shutdown();
      for (final w in host.services.values) {
        (w as Worker).stop();
      }
    });

    ProcessPlace place() => ProcessPlace(
      endpoint: const ProcessEndpoint(port: 1, token: token),
      connector: (_) async {
        final (client, server) = PlaceLink.pair();
        host.accept(server);
        return client;
      },
      launcher: _CountingLauncher(() => launches++),
      command: const ProcessCommand('/bin/app'),
    );

    test('each worker reaches the service it names', () async {
      final p = place();
      final a = p.bind(EchoWorker(), service: 'a');
      final b = p.bind(EchoWorker(), service: 'b');
      expect(await Future.wait([a.echo('to a'), b.echo('to b')]), [
        'to a',
        'to b',
      ]);
      expect(host.links, 2);
      a.stop();
      b.stop();
    });

    test('an unknown or missing name is refused without a relaunch', () async {
      final p = place();
      final c = p.bind(EchoWorker(), service: 'c');
      await expectLater(
        c.echo(1),
        throwsA(
          isA<WorkerException>().having(
            (e) => e.message,
            'message',
            contains('unknown service c'),
          ),
        ),
      );
      final unnamed = p.bind(EchoWorker());
      await expectLater(
        unnamed.echo(1),
        throwsA(
          isA<WorkerException>().having(
            (e) => e.message,
            'message',
            contains('a, b'),
          ),
        ),
      );
      expect(launches, 0);
      c.stop();
      unnamed.stop();
    });
  });
}

Future<void> _until(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in time');
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

class _CountingLauncher implements ProcessLauncher {
  _CountingLauncher(this.onLaunch);
  final void Function() onLaunch;
  @override
  Future<LaunchedProcess> launch(ProcessCommand command) {
    onLaunch();
    throw StateError('no launch expected');
  }
}
