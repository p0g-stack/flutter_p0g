import 'dart:async';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/process.dart' show exitWithHooks;
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/context/tool_dependencies.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'commands/build.dart';
import 'commands/create.dart';
import 'commands/devices.dart';
import 'commands/install.dart';
import 'commands/logs.dart';
import 'commands/precache.dart';
import 'commands/run.dart';
import 'context.dart';
import 'runner.dart';

@visibleForTesting
P0gCommandRunner createRunner(ToolDependencies deps, {bool verboseHelp = false}) {
  return P0gCommandRunner(
      analytics: deps.analytics,
      featureFlags: deps.featureFlags,
      toolContext: deps.toolContext,
      verboseHelp: verboseHelp,
    )
    ..addCommand(CreateCommand())
    ..addCommand(P0gBuildCommand(deps, verboseHelp: verboseHelp))
    ..addCommand(DevicesCommand())
    ..addCommand(InstallCommand())
    ..addCommand(LogsCommand())
    ..addCommand(RunCommand(verboseHelp: verboseHelp))
    ..addCommand(PrecacheCommand());
}

Future<void> main(List<String> args) async {
  final verbose = args.contains('-v') || args.contains('--verbose');
  final help =
      args.contains('-h') || args.contains('--help') || (args.isNotEmpty && args.first == 'help');
  Cache.flutterRoot = await flutterRootOfThisTool();

  await runInP0gContext(() async {
    final deps = await ToolDependencies.bootstrap(
      analytics: globals.analytics,
      artifacts: globals.artifacts,
      buildSystem: globals.buildSystem,
      buildTargets: globals.buildTargets,
      cache: globals.cache,
      config: globals.config,
      featureFlags: featureFlags,
      fs: globals.fs,
      flutterVersion: globals.flutterVersion,
      logger: globals.logger,
      outputPreferences: globals.outputPreferences,
      processManager: globals.processManager,
      projectFactory: globals.projectFactory,
      shutdownHooks: globals.shutdownHooks,
      stdio: globals.stdio,
      terminal: globals.terminal,
    );
    final runner = createRunner(deps, verboseHelp: help && verbose);
    // Errors outside the command's own future (the resident runner's
    // terminal handler) end the tool the same way, running shutdown hooks,
    // as flutter_tools' runner zone does.
    final done = Completer<int>();
    runZonedGuarded(
      () async {
        await runner.run(args);
        if (!done.isCompleted) done.complete(0);
      },
      (error, stack) {
        if (done.isCompleted) return;
        done.complete(switch (error) {
          ToolExit(:final message, :final exitCode) => () {
            if (message != null) globals.printError(message);
            return exitCode ?? 1;
          }(),
          UsageException(:final message, :final usage) => () {
            globals.printError(message);
            globals.printStatus(usage);
            return 64;
          }(),
          _ => () {
            globals.printError('$error\n$stack');
            return 1;
          }(),
        });
      },
    );
    await exitWithHooks(await done.future, shutdownHooks: globals.shutdownHooks);
  }, verbose: verbose);
}

/// The Flutter SDK this tool was resolved against: flutter_tools lives at
/// `<root>/packages/flutter_tools`, as flutterpi_tool finds it.
Future<String> flutterRootOfThisTool() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_tools/'));
  if (lib == null) throw StateError('Cannot locate the resolved flutter_tools package.');
  return p.normalize(p.join(lib.toFilePath(), '..', '..', '..'));
}
