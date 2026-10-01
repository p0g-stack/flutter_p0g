import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  test('runs in-process', () async {
    final service = HelloService();
    expect(await service.hello('p0g'), 'Hello, p0g!');
    expect(await service.count(3).toList(), [1, 2, 3]);
  });

  test('runs in an isolate through its Squadron worker', () async {
    final worker = HelloServiceWorker();
    addTearDown(worker.terminate);
    expect(await worker.hello('worker'), 'Hello, worker!');
    expect(await worker.count(3).toList(), [1, 2, 3]);
    final facts = Facts.fromMap(await worker.facts());
    expect(facts[Fact.processSpawn], isA<bool>());
  }, testOn: 'vm');

  test("the worker's logs reach the caller's log", () async {
    final lines = <String>[];
    final stop = logTo(lines.add, level: Level.ALL);
    addTearDown(stop);
    final worker = withLogs(HelloServiceWorker());
    addTearDown(worker.terminate);
    await worker.hello('logs');
    await pumpEventQueue();
    expect(lines, contains(endsWith('FINE service.hello: hello logs')));
  });
}
