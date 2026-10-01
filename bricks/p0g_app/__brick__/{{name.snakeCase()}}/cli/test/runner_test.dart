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

  test('serve needs a known service', () async {
    expect(await AppRunner().run(['serve', 'nope']), 64);
  });

  test('the CLI checks its own facts', () async {
    final place = await cliPlace();
    expect(place.kind, 'cli');
    expect(place.facts[Fact.processSpawn], isA<bool>());
  });
}
