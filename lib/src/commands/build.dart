import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import 'build_webui.dart';

/// `build webui` and `build aera`, as `flutter build <target>`.
class P0gBuildCommand extends FlutterCommand {
  P0gBuildCommand({bool verboseHelp = false}) {
    addSubcommand(BuildWebUiCommand(verboseHelp: verboseHelp));
    addSubcommand(BuildAeraCommand());
  }

  @override
  final name = 'build';

  @override
  final description = 'Build an app for a p0g target.';

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}

/// Stub until flutter-aera fixes the `.aerap` layout and releases the AERA
/// engine kits that `precache --aera` will fetch.
class BuildAeraCommand extends FlutterCommand {
  BuildAeraCommand() {
    requiresPubspecYaml();
  }

  @override
  final name = 'aera';

  @override
  final description = 'Build an AERA plugin (.aerap). Not available yet.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    throwToolExit(
      'build aera is not available yet: it waits on the .aerap layout and '
      'engine kits from flutter-aera.',
    );
  }
}
