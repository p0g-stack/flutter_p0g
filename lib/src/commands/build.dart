import 'package:flutter_tools/src/runner/flutter_command.dart';

import 'build_aera.dart';
import 'build_webui.dart';

/// `build webui` and `build aera`, as `flutter build <target>`.
class P0gBuildCommand extends FlutterCommand {
  P0gBuildCommand({bool verboseHelp = false}) {
    addSubcommand(BuildWebUiCommand(verboseHelp: verboseHelp));
    addSubcommand(BuildAeraCommand(verboseHelp: verboseHelp));
  }

  @override
  final name = 'build';

  @override
  final description = 'Build an app for a p0g target.';

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}
