import 'package:args/command_runner.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// Calls [HelloService] in-process.
class HelloCommand extends Command<int> {
  HelloCommand() {
    argParser.addOption('count', abbr: 'c', help: 'Also count to N.');
  }

  @override
  String get name => 'hello';

  @override
  String get description => 'Say hello through the hello service.';

  @override
  String get invocation => '${runner!.executableName} hello <who>';

  @override
  Future<int> run() async {
    final service = HelloService();
    final who = argResults!.rest.isEmpty ? 'world' : argResults!.rest.first;
    print(await service.hello(who));
    final count = int.tryParse(argResults!.option('count') ?? '');
    if (count != null) {
      await service.count(count).forEach(print);
    }
    return 0;
  }
}
