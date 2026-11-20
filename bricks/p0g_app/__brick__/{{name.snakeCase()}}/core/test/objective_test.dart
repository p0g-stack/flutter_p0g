import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

final class OnDevice extends ReadStrategy<String, String> {
  const OnDevice();
  @override
  String get name => 'on_device';
  @override
  Set<String> get requires => const {Fact.root};
  @override
  Future<String> run(String input, PlaceInfo place) async => 'device:$input';
}

final class FromHost extends ReadStrategy<String, String> {
  const FromHost();
  @override
  String get name => 'from_host';
  @override
  Set<String> get requires => const {Fact.usbNative};
  @override
  Future<String> run(String input, PlaceInfo place) async => 'host:$input';
}

/// A host-side strategy whose phone may not be plugged in yet.
final class OverUsb extends ReadStrategy<String, String> {
  OverUsb({this.plugged = false});
  final bool plugged;
  @override
  String get name => 'over_usb';
  @override
  Set<String> get requires => const {Fact.usbNative};
  @override
  Availability available(Facts facts) {
    final base = super.available(facts);
    if (!base.ok || plugged) return base;
    return Availability(name, note: 'connect a phone', waiting: true);
  }

  @override
  Future<String> run(String input, PlaceInfo place) async => 'usb:$input';
}

final class Flash extends WriteStrategy<String, int> {
  final written = <String>[];
  @override
  String get name => 'flash';
  @override
  Set<String> get requires => const {Fact.blockDevices};
  @override
  Future<List<String>> plan(String input, PlaceInfo place) async => [
    'write $input',
  ];
  @override
  Future<int> write(String input, PlaceInfo place) async {
    written.add(input);
    return input.length;
  }
}

void main() {
  final records = <LogRecord>[];
  setUp(() {
    records.clear();
    Logger.root.level = Level.ALL;
  });
  Logger.root.onRecord.listen(records.add);

  final root = PlaceInfo('process', Facts({Fact.root: true}));
  final host = PlaceInfo('cli', Facts({Fact.usbNative: true}));
  const page = PlaceInfo('web_worker', Facts.none());
  final blocks = PlaceInfo('process', Facts({Fact.blockDevices: true}));

  group('Objective.run', () {
    final fetch = Objective<String, String>('fetch', const [
      OnDevice(),
      FromHost(),
    ]);

    test('picks the first available strategy from facts', () async {
      expect(await fetch.run('boot', root), 'device:boot');
      expect(await fetch.run('boot', host), 'host:boot');
    });

    test('logs which strategy ran, where, with which facts, and why', () async {
      await fetch.run('boot', host);
      final run = records.map((r) => r.object).whereType<StrategyRun>().single;
      expect(run.strategy, 'from_host');
      expect(run.place, 'cli');
      expect(run.facts, [Fact.usbNative]);
      expect(run.why, 'on_device skipped (missing root); from_host chosen');
      expect(run.outcome, 'ok');
    });

    test('says why nothing fits', () {
      expect(
        () => fetch.run('boot', page),
        throwsA(
          isA<NoStrategyAvailable>().having(
            (e) => e.why,
            'why',
            'nothing fits: on_device skipped (missing root); '
                'from_host skipped (missing usb.native)',
          ),
        ),
      );
    });
  });

  group('waiting for the user', () {
    test('a waiting strategy is offered, not chosen', () {
      final fetch = Objective<String, String>('fetch', [
        OverUsb(),
        const FromHost(),
      ]);
      final s = fetch.selectRead(host);
      expect(s.chosen, isA<FromHost>());
      expect(s.waiting.single.$1, isA<OverUsb>());
      expect(s.why, 'over_usb waits: connect a phone; from_host chosen');
    });

    test('missing facts win over waiting', () {
      final s = Objective<String, String>('fetch', [OverUsb()]).selectRead(page);
      expect(s.waiting, isEmpty);
      expect(s.why, 'nothing fits: over_usb skipped (missing usb.native)');
    });

    test('once the phone is plugged in, it runs', () async {
      final fetch = Objective<String, String>('fetch', [OverUsb(plugged: true)]);
      expect(await fetch.run('boot', host), 'usb:boot');
    });
  });

  group('device writes', () {
    test('plan, then confirm, then receipt', () async {
      final flash = Flash();
      final objective = Objective<String, int>('flash', [flash]);

      final plan = await objective.plan('boot.img', blocks);
      expect(flash.written, isEmpty, reason: 'planning writes nothing');
      expect(plan.steps, ['write boot.img']);

      final receipt = await objective.apply(plan, Confirmation.of(plan));
      expect(flash.written, ['boot.img']);
      expect(receipt.result, 8);
      expect(receipt.run.write, isTrue);
    });

    test('a confirmation is only good for its own plan', () async {
      final objective = Objective<String, int>('flash', [Flash()]);
      final a = await objective.plan('a', blocks);
      final b = await objective.plan('b', blocks);
      expect(() => objective.apply(b, Confirmation.of(a)), throwsStateError);
    });

    test('run never picks a write strategy', () {
      final objective = Objective<String, int>('flash', [Flash()]);
      expect(
        () => objective.run('a', blocks),
        throwsA(isA<NoStrategyAvailable>()),
      );
    });
  });
}
