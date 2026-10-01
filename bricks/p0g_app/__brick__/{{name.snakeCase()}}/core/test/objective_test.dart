import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

final class OnDevice extends ReadStrategy<String, String> {
  const OnDevice();
  @override
  String get name => 'on_device';
  @override
  bool available(Facts facts) => facts.has(Fact.root);
  @override
  Future<String> run(String input, Place place) async => 'device:$input';
}

final class FromHost extends ReadStrategy<String, String> {
  const FromHost();
  @override
  String get name => 'from_host';
  @override
  bool available(Facts facts) => facts.has(Fact.usbNative);
  @override
  Future<String> run(String input, Place place) async => 'host:$input';
}

final class Flash extends WriteStrategy<String, int> {
  final written = <String>[];
  @override
  String get name => 'flash';
  @override
  bool available(Facts facts) => facts.has(Fact.blockDevices);
  @override
  Future<List<String>> plan(String input, Place place) async => [
    'write $input',
  ];
  @override
  Future<int> write(String input, Place place) async {
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

  const root = Place('process', Facts({Fact.root: true}));
  const host = Place('cli', Facts({Fact.usbNative: true}));
  const page = Place('main');

  group('Objective.run', () {
    final fetch = Objective<String, String>('fetch', const [
      OnDevice(),
      FromHost(),
    ]);

    test('picks the first available strategy from facts', () async {
      expect(await fetch.run('boot', root), 'device:boot');
      expect(await fetch.run('boot', host), 'host:boot');
    });

    test('logs which strategy ran, where, with which facts', () async {
      await fetch.run('boot', root);
      final run = records.map((r) => r.object).whereType<StrategyRun>().single;
      expect(run.strategy, 'on_device');
      expect(run.place, 'process');
      expect(run.facts, [Fact.root]);
      expect(run.outcome, 'ok');
    });

    test('throws when nothing is available', () {
      expect(
        () => fetch.run('boot', page),
        throwsA(isA<NoStrategyAvailable>()),
      );
    });
  });

  group('device writes', () {
    test('plan, then confirm, then receipt', () async {
      final flash = Flash();
      final objective = Objective<String, int>('flash', [flash]);
      const place = Place('process', Facts({Fact.blockDevices: true}));

      final plan = await objective.plan('boot.img', place);
      expect(flash.written, isEmpty, reason: 'planning writes nothing');
      expect(plan.steps, ['write boot.img']);

      final receipt = await objective.apply(plan, Confirmation.of(plan));
      expect(flash.written, ['boot.img']);
      expect(receipt.result, 8);
      expect(receipt.run.write, isTrue);
    });

    test('a confirmation is only good for its own plan', () async {
      final objective = Objective<String, int>('flash', [Flash()]);
      const place = Place('process', Facts({Fact.blockDevices: true}));
      final a = await objective.plan('a', place);
      final b = await objective.plan('b', place);
      expect(() => objective.apply(b, Confirmation.of(a)), throwsStateError);
    });

    test('run never picks a write strategy', () {
      final objective = Objective<String, int>('flash', [Flash()]);
      const place = Place('process', Facts({Fact.blockDevices: true}));
      expect(
        () => objective.run('a', place),
        throwsA(isA<NoStrategyAvailable>()),
      );
    });
  });
}
