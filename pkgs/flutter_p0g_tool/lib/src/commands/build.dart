import 'package:flutter_tools/src/context/tool_dependencies.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import 'build_aera.dart';
import 'build_web.dart';
import 'build_webui.dart';

/// `build web`, `build webui` and `build aera`, as `flutter build <target>`.
class P0gBuildCommand extends FlutterCommand {
  P0gBuildCommand(ToolDependencies deps, {bool verboseHelp = false}) {
    addSubcommand(
      BuildWebP0gCommand(
        toolContext: deps.toolContext,
        buildSystem: deps.buildSystem,
        featureFlags: deps.featureFlags,
        verboseHelp: verboseHelp,
      ),
    );
    addSubcommand(
      BuildWebUiCommand(
        toolContext: deps.toolContext,
        buildSystem: deps.buildSystem,
        featureFlags: deps.featureFlags,
        verboseHelp: verboseHelp,
      ),
    );
    addSubcommand(
      BuildAeraCommand(
        toolContext: deps.toolContext,
        buildSystem: deps.buildSystem,
        featureFlags: deps.featureFlags,
        verboseHelp: verboseHelp,
      ),
    );
  }

  @override
  final name = 'build';

  @override
  final description = 'Build an app for a p0g target.';

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}
