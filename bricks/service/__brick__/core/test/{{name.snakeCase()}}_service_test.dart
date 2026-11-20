import 'package:test/test.dart';
import 'package:{{app}}_core/{{app}}_core.dart';

void main() {
  test('runs in-process', () async {
    expect(await {{name.pascalCase()}}Service().echo('p0g'), 'p0g');
  });

  test('runs in an isolate through its Squadron worker', () async {
    final worker = {{name.pascalCase()}}ServiceWorker();
    addTearDown(worker.terminate);
    expect(await worker.echo('worker'), 'worker');
  }, testOn: 'vm');
}
