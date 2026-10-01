import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_cli/{{name.snakeCase()}}_cli.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

void main() {
  test('hello runs', () async {
    expect(await AppRunner().run(['hello', 'cli']), 0);
  });

  test('an unknown command is a usage error', () async {
    expect(await AppRunner().run(['nope']), 64);
  });

  test('facts are checked, and process.spawn is among them', () async {
    final facts = await probeFacts();
    expect(facts[Fact.processSpawn], isNotNull);
    expect(facts[Fact.root], isA<bool>());
  }, testOn: 'linux || mac-os');
}
