import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

{{#rust}}import 'commands/digest_command.dart';
{{/rust}}import 'commands/facts_command.dart';
import 'commands/hello_command.dart';
import 'commands/serve_command.dart';
// p0g:imports (bricks insert imports above this line)

/// The `{{name.snakeCase()}}` command runner.
class AppRunner extends CommandRunner<int> {
  AppRunner() : super('{{name.snakeCase()}}', r'''{{{description}}}''') {
    argParser
      ..addFlag('verbose', abbr: 'v', help: 'Log everything.')
      ..addFlag('json', help: 'Log records as JSON lines.');
{{#rust}}    addCommand(DigestCommand());
{{/rust}}    addCommand(FactsCommand());
    addCommand(HelloCommand());
    addCommand(ServeCommand());
    // p0g:commands (bricks insert commands above this line)
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      return await super.run(args) ?? 0;
    } on UsageException catch (e) {
      stderr.writeln(e);
      return 64;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    final stop = logTo(
      stderr.writeln,
      level: topLevelResults.flag('verbose') ? Level.ALL : Level.INFO,
      json: topLevelResults.flag('json'),
    );
    try {
      return await super.runCommand(topLevelResults);
    } finally {
      stop();
    }
  }
}

/// The CLI running a command itself, with facts checked here.
Future<PlaceInfo> cliPlace() async => PlaceInfo('cli', Facts(await checkFacts()));
