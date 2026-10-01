import 'dart:async';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/process.dart' show exitWithHooks;
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import 'commands/build.dart';
import 'commands/create.dart';
import 'commands/install.dart';
import 'commands/precache.dart';
import 'commands/run.dart';
import 'context.dart';
import 'runner.dart';

@visibleForTesting
P0gCommandRunner createRunner({bool verboseHelp = false}) {
  return P0gCommandRunner(verboseHelp: verboseHelp)
    ..addCommand(CreateCommand())
    ..addCommand(P0gBuildCommand(verboseHelp: verboseHelp))
    ..addCommand(InstallCommand())
    ..addCommand(RunCommand())
    ..addCommand(PrecacheCommand());
}

Future<void> main(List<String> args) async {
  final verbose = args.contains('-v') || args.contains('--verbose');
  final help =
      args.contains('-h') || args.contains('--help') || (args.isNotEmpty && args.first == 'help');
  Cache.flutterRoot = await flutterRootOfThisTool();

  await runInP0gContext(() async {
    final runner = createRunner(verboseHelp: help && verbose);
    var code = 0;
    try {
      await runner.run(args);
    } on ToolExit catch (e) {
      if (e.message != null) globals.printError(e.message!);
      code = e.exitCode ?? 1;
    } on UsageException catch (e) {
      globals.printError(e.message);
      globals.printStatus(e.usage);
      code = 64;
    }
    await exitWithHooks(code, shutdownHooks: globals.shutdownHooks);
  }, verbose: verbose);
}

/// The Flutter SDK this tool was resolved against: flutter_tools lives at
/// `<root>/packages/flutter_tools`, as flutterpi_tool finds it.
Future<String> flutterRootOfThisTool() async {
  final config = await findPackageConfigUri(io.Platform.script);
  if (config == null) {
    throw StateError('flutter_p0g must run from its package (no package_config.json).');
  }
  final tools = config.resolve(Uri.parse('package:flutter_tools/'))!.toFilePath();
  return p.dirname(p.dirname(p.dirname(tools)));
}
