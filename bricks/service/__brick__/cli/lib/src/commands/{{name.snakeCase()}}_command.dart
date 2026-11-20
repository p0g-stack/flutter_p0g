import 'package:args/command_runner.dart';
import 'package:{{app}}_core/{{app}}_core.dart';

/// Calls [{{name.pascalCase()}}Service] in-process.
class {{name.pascalCase()}}Command extends Command<int> {
  @override
  String get name => '{{name.paramCase()}}';

  @override
  String get description => 'Call the {{name.snakeCase()}} service.';

  @override
  String get invocation => '${runner!.executableName} {{name.paramCase()}} <input>';

  @override
  Future<int> run() async {
    final input = argResults!.rest.join(' ');
    print(await {{name.pascalCase()}}Service().echo(input));
    return 0;
  }
}
