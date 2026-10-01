@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cancelation_token/cancelation_token.dart';
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:squadron_process/src/protocol.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';
import 'support/fakes.dart';

const token = 'secret-token';

void main() {
  group('malformed handshakes', () {
    late PlaceHost host;
    setUp(
      () => host = PlaceHost(
        services: {'echo': EchoWorker()},
        token: token,
        firstLinkGrace: const Duration(seconds: 5),
      ),
    );
    tearDown(() async {
      await host.shutdown();
      (host.services.values.single as Worker).stop();
    });

    /// Sends [frame] as the first frame of a new link and returns the host's
    /// answer.
    Future<List> firstAnswer(Uint8List frame) async {
      final (client, server) = PlaceLink.pair();
      host.accept(server);
      final answer = client.frames.first;
      client.send(frame);
      return Msg.decode(await answer);
    }

    Uint8List enc(Object? v) => PlaceCodec.encode(v);

    final cases = <String, (Uint8List, String)>{
      'bytes that are not a message': (
        Uint8List.fromList([0xff, 0x00, 0x13]),
        'bad hello',
      ),
      'a value that is not a list': (enc('hello'), 'bad hello'),
      'an empty list': (enc([]), 'bad hello'),
      'a list not led by a type': (enc(['hello', 1]), 'bad hello'),
      'a request before hello': (
        enc([Msg.request, 1, 1, [], null, false]),
        'expected hello',
      ),
      'a hello without a token': (
        enc([Msg.hello, Msg.version]),
        'expected hello',
      ),
      'another protocol version': (
        enc([Msg.hello, 99, token]),
        'protocol 99 unsupported',
      ),
      'a token that is not a string': (
        enc([Msg.hello, Msg.version, 42]),
        'bad token',
      ),
      'a service name that is not a string': (
        enc([Msg.hello, Msg.version, token, 7]),
        'bad service name',
      ),
      'an oversized hello': (
        enc([Msg.hello, Msg.version, token, 'x' * 5000]),
        'bad hello',
      ),
    };

    for (final MapEntry(key: name, value: (frame, reason)) in cases.entries) {
      test('$name is refused and the host keeps serving', () async {
        final answer = await firstAnswer(frame);
        expect(answer, [Msg.refused, contains(reason)]);
        expect(host.links, 0);
        expect(host.isDone, isFalse);

        final (client, server) = PlaceLink.pair();
        host.accept(server);
        final channel = await ProcessChannel.connect(client, token: token);
        expect(await channel.sendRequest(EchoService.echoCmd, ['ok']), 'ok');
        await channel.close();
      });
    }

    test('only the first frame is taken as the hello', () async {
      final (client, server) = PlaceLink.pair();
      host.accept(server);
      final frames = <List>[];
      final sub = client.frames.listen((f) => frames.add(Msg.decode(f)));
      client.send(enc([Msg.hello, Msg.version, 'wrong']));
      client.send(enc([Msg.hello, Msg.version, token]));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(frames, [
        [Msg.refused, 'bad token'],
      ]);
      expect(host.links, 0);
      await sub.cancel();
    });
  });

  group('malformed messages after the handshake', () {
    late PlaceHost host;
    late PlaceLink link;
    late StreamIterator<Uint8List> answers;

    setUp(() async {
      host = PlaceHost(services: {'echo': EchoWorker()}, token: token);
      final (client, server) = PlaceLink.pair();
      host.accept(server);
      final h = await ProcessHandshake.run(client, token: token);
      link = h.link;
      answers = StreamIterator(link.frames);
    });
    tearDown(() async {
      await answers.cancel();
      await host.shutdown();
      (host.services.values.single as Worker).stop();
    });

    /// The next answer, skipping relayed log records.
    Future<List> next() async {
      while (true) {
        expect(await answers.moveNext(), isTrue);
        final m = Msg.decode(answers.current);
        if (m[0] != Msg.log) return m;
      }
    }

    void send(List m) => link.send(Msg.encode(m));

    test('fail the request they name and leave the link working', () async {
      link.send(Uint8List.fromList([0xff, 0xfe]));
      send([Msg.request, 'not an id', 1, [], null, false]);
      send([Msg.cancel]);
      send([Msg.unlisten]);
      send([Msg.request, 5, 'not a command', [], null, false]);
      final error = await next();
      expect(error[0], Msg.error);
      expect(error[1], 5);

      send([
        Msg.request,
        6,
        EchoService.echoCmd,
        ['ok'],
        null,
        false,
      ]);
      expect(await next(), [Msg.value, 6, 'ok']);
      expect(host.links, 1);
      expect(host.isDone, isFalse);
    });

    test('a request id already in use is ignored', () async {
      send([
        Msg.request,
        9,
        EchoService.waitCmd,
        [100],
        null,
        false,
      ]);
      send([
        Msg.request,
        9,
        EchoService.echoCmd,
        ['dup'],
        null,
        false,
      ]);
      expect(await next(), [Msg.value, 9, 'finished']);
      send([
        Msg.request,
        10,
        EchoService.echoCmd,
        ['next'],
        null,
        false,
      ]);
      expect(await next(), [Msg.value, 10, 'next']);
    });
  });

  group('a client facing a malformed welcome', () {
    Future<Object?> handshakeWith(Uint8List answer) async {
      final (client, server) = PlaceLink.pair();
      final closed = Completer<void>();
      server.frames.listen((_) => server.send(answer), onDone: closed.complete);
      try {
        await ProcessHandshake.run(client, token: token);
        return null;
      } catch (e) {
        await closed.future; // the client closed its end
        return e;
      }
    }

    test('rejects bytes that are not a message', () async {
      expect(
        await handshakeWith(Uint8List.fromList([0xff])),
        isA<WorkerException>().having(
          (e) => e.message,
          'message',
          contains('Malformed handshake'),
        ),
      );
    });

    test('rejects a welcome without facts', () async {
      expect(
        await handshakeWith(
          Msg.encode([Msg.welcome, Msg.version, PlaceKind.process]),
        ),
        isA<WorkerException>().having(
          (e) => e.message,
          'message',
          contains('Unexpected handshake'),
        ),
      );
    });

    test('rejects a welcome of another version', () async {
      expect(
        await handshakeWith(
          Msg.encode([Msg.welcome, 2, PlaceKind.process, {}]),
        ),
        isA<WorkerException>(),
      );
    });
  });

  group('reconnect', () {
    late FakeLauncher launcher;
    late ProcessPlace place;
    const command = ProcessCommand('/opt/demo/bin/demo');
    final clientEnds = <PlaceLink>[];

    setUp(() {
      launcher = FakeLauncher();
      clientEnds.clear();
      place = ProcessPlace(
        launcher: launcher,
        command: command,
        connector: (e) async {
          final link = await launcher.connect(e);
          clientEnds.add(link);
          return link;
        },
      );
    });
    tearDown(() => launcher.dispose());

    test('after a dropped link, the next call opens a new one', () async {
      final w = place.bind(EchoWorker());
      expect(await w.echo(1), 1);
      final pending = w.wait(10000);
      await Future.delayed(const Duration(milliseconds: 20));
      await clientEnds.last.close();
      await expectLater(
        pending,
        throwsA(
          isA<WorkerException>().having(
            (e) => e.message,
            'message',
            contains('link is gone'),
          ),
        ),
      );

      expect(await w.echo(2), 2);
      expect(await w.count(3).toList(), [0, 1, 2]);
      expect(clientEnds, hasLength(2));
      expect(launcher.commands, hasLength(1)); // same host
      expect(launcher.hosts.values.single.links, 1);
      w.stop();
    });

    test('a stream started while unlinked reconnects too', () async {
      final w = place.bind(EchoWorker());
      expect(await w.echo(1), 1);
      await clientEnds.last.close();
      await Future.delayed(Duration.zero);
      expect(await w.count(4).toList(), [0, 1, 2, 3]);
      w.stop();
    });

    test('a host that died is started again on the next call', () async {
      final w = place.bind(EchoWorker());
      expect(await w.echo(1), 1);
      await launcher.hosts[4000]!.shutdown('killed');
      await Future.delayed(Duration.zero);

      expect(await w.echo(2), 2);
      expect(launcher.commands, hasLength(2));
      expect(place.endpoint!.port, 4001);
      expect(await place.facts(), PlaceFacts({'root': true, 'port': 4001}));
      w.stop();
    });

    test('workers that lose their host together start one new host', () async {
      final workers = List.generate(5, (_) => place.bind(EchoWorker()));
      await Future.wait([for (final w in workers) w.echo(0)]);
      expect(launcher.commands, hasLength(1));

      await launcher.hosts[4000]!.shutdown('killed');
      await Future.delayed(Duration.zero);
      final got = await Future.wait([
        for (var i = 0; i < workers.length; i++) workers[i].echo(i),
      ]);
      expect(got, [0, 1, 2, 3, 4]);
      expect(launcher.commands, hasLength(2));
      for (final w in workers) {
        w.stop();
      }
    });

    test(
      'a failed reconnect fails that call; a later one can succeed',
      () async {
        final w = place.bind(EchoWorker());
        expect(await w.echo(1), 1);
        final short = ProcessPlace(
          launcher: launcher,
          command: command,
          connector: launcher.connect,
          readyTimeout: const Duration(milliseconds: 100),
        );
        final w2 = short.bind(EchoWorker());
        expect(await w2.echo('a'), 'a');
        launcher.silent = true; // the next host never reports ready
        await launcher.hosts[4001]!.shutdown('killed');
        await Future.delayed(Duration.zero);
        await expectLater(w2.echo('b'), throwsA(isA<WorkerException>()));

        launcher.silent = false;
        expect(await w2.echo('c'), 'c');
        w.stop();
        w2.stop();
      },
    );

    test('a stopped worker does not reconnect', () async {
      final w = place.bind(EchoWorker());
      expect(await w.echo(1), 1);
      w.stop();
      await expectLater(w.echo(2), throwsA(isA<WorkerException>()));
      expect(clientEnds, hasLength(1));
    });
  });

  group('concurrent clients', () {
    late PlaceHost host;
    setUp(
      () => host = PlaceHost(
        services: {'echo': EchoWorker()},
        token: token,
        grace: const Duration(milliseconds: 200),
      ),
    );
    tearDown(() async {
      await host.shutdown();
      (host.services.values.single as Worker).stop();
    });

    // Each client is its own ProcessPlace, as separate client processes
    // would be.
    EchoWorker client() => ProcessPlace(
      endpoint: const ProcessEndpoint(port: 1, token: token),
      connector: (_) async {
        final (c, s) = PlaceLink.pair();
        host.accept(s);
        return c;
      },
    ).bind(EchoWorker());

    test('calls and streams from several clients run side by side', () async {
      final clients = List.generate(4, (_) => client());
      final results = await Future.wait([
        for (var i = 0; i < clients.length; i++)
          Future.wait([
            clients[i].echo('c$i'),
            clients[i].count(i + 2, delayMs: 5).toList(),
            clients[i].wait(30),
          ]),
      ]);
      for (var i = 0; i < clients.length; i++) {
        expect(results[i], ['c$i', List.generate(i + 2, (j) => j), 'finished']);
      }
      expect(host.links, 4);
      for (final c in clients) {
        c.stop();
      }
    });

    test('one client cancelling does not touch another\'s work', () async {
      final a = client(), b = client();
      final ta = CancelableToken();
      final ca = a.wait(5000, token: ta);
      final cb = b.wait(150, token: CancelableToken());
      await Future.delayed(const Duration(milliseconds: 30));
      ta.cancel();
      await expectLater(ca, throwsA(isA<CanceledException>()));
      expect(await cb, 'finished');
      a.stop();
      b.stop();
    });

    test('one client leaving does not touch another\'s work', () async {
      final a = client(), b = client();
      expect(await a.echo(1), 1);
      final cb = b.wait(300);
      await Future.delayed(const Duration(milliseconds: 20));
      a.stop();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(host.links, 1);
      expect(await cb, 'finished');
      expect(host.isDone, isFalse);
      b.stop();
    });

    test('many workers starting at once launch one host', () async {
      final launcher = FakeLauncher();
      final place = ProcessPlace(
        launcher: launcher,
        command: const ProcessCommand('/opt/demo/bin/demo'),
        connector: launcher.connect,
      );
      final workers = List.generate(10, (_) => place.bind(EchoWorker()));
      final got = await Future.wait([
        for (var i = 0; i < workers.length; i++) workers[i].echo(i),
      ]);
      expect(got, List.generate(10, (i) => i));
      expect(launcher.commands, hasLength(1));
      expect(launcher.hosts.values.single.links, 10);
      for (final w in workers) {
        w.stop();
      }
      await launcher.dispose();
    });
  });
}
