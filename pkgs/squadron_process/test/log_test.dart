@TestOn('vm')
library;

import 'package:logger/logger.dart';
import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

import 'support/echo_service.dart';

const token = 'secret-token';

/// Keeps what it is asked to log.
class Capture extends Logger {
  Capture() : super(output: MemoryOutput());
  final records = <(Level, Object?, Object?, DateTime?)>[];

  @override
  void log(
    Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) => records.add((level, message, error, time));
}

void main() {
  late PlaceHost host;
  late EchoWorker hosted;
  late Capture hostSide;

  setUp(() {
    hostSide = Capture();
    hosted = EchoWorker()..channelLogger = hostSide;
    host = PlaceHost(services: {'echo': hosted}, token: token);
  });
  tearDown(() async {
    await host.shutdown();
    hosted.stop();
  });

  ProcessPlace place() => ProcessPlace(
    endpoint: const ProcessEndpoint(port: 1, token: token),
    connector: (_) async {
      final (c, s) = PlaceLink.pair();
      host.accept(s);
      return c;
    },
  );

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 50));

  test(
    'service log records reach the client worker\'s channelLogger',
    () async {
      final client = Capture();
      final w = place().bind(EchoWorker()..channelLogger = client);
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      expect(await w.log('from the host'), isTrue);
      await settle();

      final (level, message, error, time) = client.records.singleWhere(
        (r) => '${r.$2}'.contains('from the host'),
      );
      expect(level, Level.warning);
      expect(message, 'from the host');
      expect(error, 'oops');
      expect(time!.isAfter(before), isTrue);
      w.stop();
    },
  );

  test('the host\'s own channelLogger still gets them', () async {
    final w = place().bind(EchoWorker());
    await w.log('teed');
    await settle();
    expect(hostSide.records.map((r) => r.$2), contains('teed'));
    w.stop();
  });

  test('several links from one client get each record once', () async {
    // One page binding the service in several places: one client id.
    final a = Capture(), b = Capture();
    final wa = place().bind(EchoWorker()..channelLogger = a);
    final wb = place().bind(EchoWorker()..channelLogger = b);
    final quiet = place().bind(EchoWorker());
    await Future.wait([wa.echo(0), wb.echo(0), quiet.echo(0)]);
    expect(host.links, 3);
    await wb.log('once');
    await settle();
    final got = [...a.records, ...b.records].where((r) => r.$2 == 'once');
    expect(got, hasLength(1));
    for (final w in [wa, wb, quiet]) {
      w.stop();
    }
  });

  test('each client gets each record once; none needs a logger', () async {
    ProcessPlace placeAs(String id) => ProcessPlace(
      endpoint: const ProcessEndpoint(port: 1, token: token),
      clientId: id,
      connector: (_) async {
        final (c, s) = PlaceLink.pair();
        host.accept(s);
        return c;
      },
    );
    final a = Capture(), b = Capture();
    final wa = placeAs('client-a').bind(EchoWorker()..channelLogger = a);
    final wb = placeAs('client-b').bind(EchoWorker()..channelLogger = b);
    final quiet = placeAs('client-c').bind(EchoWorker());
    await Future.wait([wa.echo(0), wb.echo(0), quiet.echo(0)]);
    await quiet.log('to all');
    await settle();
    expect(a.records.where((r) => r.$2 == 'to all'), hasLength(1));
    expect(b.records.where((r) => r.$2 == 'to all'), hasLength(1));
    for (final w in [wa, wb, quiet]) {
      w.stop();
    }
  });

  test(
    'when a client\'s receiving link closes, another of its links takes over',
    () async {
      final a = Capture(), b = Capture();
      final wa = place().bind(EchoWorker()..channelLogger = a);
      final wb = place().bind(EchoWorker()..channelLogger = b);
      await Future.wait([wa.echo(0), wb.echo(0)]);
      wa.stop();
      await settle();
      await wb.log('still here');
      await settle();
      expect(b.records.where((r) => r.$2 == 'still here'), hasLength(1));
      wb.stop();
    },
  );

  test('records go only to links bound to the service that logged', () async {
    final other = EchoWorker();
    final two = PlaceHost(
      services: {'echo': EchoWorker(), 'other': other},
      token: token,
    );
    ProcessPlace p() => ProcessPlace(
      endpoint: const ProcessEndpoint(port: 1, token: token),
      connector: (_) async {
        final (c, s) = PlaceLink.pair();
        two.accept(s);
        return c;
      },
    );
    final onEcho = Capture(), onOther = Capture();
    final we = p().bind(EchoWorker()..channelLogger = onEcho, service: 'echo');
    final wo = p().bind(
      EchoWorker()..channelLogger = onOther,
      service: 'other',
    );
    await wo.echo(0);
    await we.log('echo only');
    await settle();
    expect(onEcho.records.map((r) => r.$2), contains('echo only'));
    expect(onOther.records.map((r) => r.$2), isNot(contains('echo only')));
    we.stop();
    wo.stop();
    await two.shutdown();
    for (final s in two.services.values) {
      (s as Worker).stop();
    }
  });
}
