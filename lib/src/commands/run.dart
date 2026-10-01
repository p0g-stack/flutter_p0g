import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

/// The dev loop. It needs flutter-webui's bootstrap (a loader that can point
/// the manager's page at a host dev server), which does not exist yet.
class RunCommand extends FlutterCommand {
  @override
  final name = 'run';

  @override
  final description = 'Run the app on a device with hot restart. Not available yet.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    throwToolExit(
      'run is not available yet: it waits on the flutter-webui bootstrap. '
      'Use `build webui` then `install`.',
    );
  }
}
