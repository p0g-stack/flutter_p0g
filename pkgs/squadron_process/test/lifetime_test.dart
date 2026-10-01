@TestOn('vm')
library;

import 'dart:async';

import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';

const token = 't';
const grace = Duration(milliseconds: 300);

void main() {
  late PlaceHost host;
  late EchoWorker service;

  setUp(() {
    service = EchoWorker();
    host = PlaceHost(
      services: {'echo': service},
      token: token,
      grace: grace,
      firstLinkGrace: const Duration(milliseconds: 300),
    );
  });

  tearDown(() async {
    await host.shutdown();
    service.stop();
  });

  Future<ProcessChannel> connect() {
    final (client, server) = PlaceLink.pair();
    host.accept(server);
    return ProcessChannel.connect(client, token: token);
  }

  test('a host nobody connects to stops after the first-link grace', () async {
    await host.done.timeout(const Duration(seconds: 2));
    expect(host.isDone, isTrue);
  });

  test('hidden keeps going: an open, idle link holds the host', () async {
    final c = await connect();
    await Future.delayed(grace * 3);
    expect(host.isDone, isFalse);
    expect(
      await c.sendRequest(EchoService.echoCmd, ['still here']),
      'still here',
    );
    await c.close();
  });

  test('a reload within the grace window keeps tasks running', () async {
    final first = await connect();
    // A long task, then the page goes away (rotation reload).
    unawaited(
      first
          .sendRequest(EchoService.waitCmd, [grace.inMilliseconds * 2])
          .catchError((_) => null),
    );
    await Future.delayed(const Duration(milliseconds: 50));
    await first.close();
    expect(host.running, 1);

    await Future.delayed(grace ~/ 2);
    final second = await connect();
    await Future.delayed(grace);
    expect(host.isDone, isFalse);
    // The task outlived the reload and finished on its own.
    await _until(() => host.running == 0);
    await second.close();
  });

  test(
    'closed stops: no link within the grace window cancels and exits',
    () async {
      final c = await connect();
      final stream = c.sendStreamingRequest(EchoService.countCmd, [100000, 5]);
      final sub = stream.listen((_) {}, onError: (_) {});
      unawaited(
        c
            .sendRequest(EchoService.waitCmd, [60000])
            .then((_) {}, onError: (_) {}),
      );
      await _until(() => host.running == 2);

      await c.close();
      final closedAt = DateTime.now();
      await host.done.timeout(const Duration(seconds: 3));
      expect(DateTime.now().difference(closedAt), greaterThanOrEqualTo(grace));
      expect(host.running, 0);
      await sub.cancel();
    },
  );

  test('a stopped host turns new links away', () async {
    await host.shutdown('test');
    await expectLater(connect(), throwsA(isA<WorkerException>()));
  });
}

Future<void> _until(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in time');
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
