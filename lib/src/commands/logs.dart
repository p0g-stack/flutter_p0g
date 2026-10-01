import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

import '../adb.dart';
import '../webui/module.dart' show readProp;

/// AERA's recovery log, which carries its plugins' output.
const kAeraLog = '/tmp/recovery.log';

/// Follows a WebUI module's root-side logs (flutter-webui
/// `docs/root-channel.md`): the root channel's `root.log` and the newest
/// detached process logs (the app's root process among them) present when
/// it starts.
@visibleForTesting
String webuiLogScript(String moduleId, {int lines = 50}) {
  final run = shellQuote('/data/adb/modules/$moduleId/webroot/.run');
  return 'cd $run 2>/dev/null || { echo "no $moduleId/webroot/.run: open the module page first" >&2; '
      'exit 3; }; '
      r'set -- root.log $(ls -t proc/*.log 2>/dev/null | head -n 4); '
      'exec tail -n $lines -F "\$@"';
}

/// The page's console: WebView logs `console.*` under the `chromium` tag.
@visibleForTesting
const kPageLogcat = ['logcat', '-v', 'time', '-T', '1', 'chromium:V', '*:S'];

/// Streams logs from the device: the WebUI module's root process and page
/// on a booted device, AERA's log (with its plugins') in recovery.
class LogsCommand extends FlutterCommand {
  LogsCommand() {
    argParser
      ..addOption('device-id', abbr: 'd', help: 'adb serial (default: the only device).')
      ..addFlag('page', defaultsTo: true, help: "webui: include the page's console (logcat).");
  }

  @override
  final name = 'logs';

  @override
  final description = "Show the app's logs from the device (WebUI module or AERA plugin).";

  @override
  Future<FlutterCommandResult> runCommand() async {
    final adb = Adb.find(stringArg('device-id'));
    final state = await adb.state();
    switch (state) {
      case 'recovery':
        globals.printStatus('AERA recovery: following $kAeraLog.');
        await adb.stream(['shell', 'tail -n 50 -F $kAeraLog']);
      case 'device':
        final prop = project.directory.childDirectory('webui').childFile('module.prop');
        final id = prop.existsSync() ? readProp(prop.readAsStringSync(), 'id') : null;
        if (id == null) throwToolExit('No id in webui/module.prop. Run `flutter_p0g create .`.');
        globals.printStatus(
          'Module $id: following its root process${boolArg('page') ? ' and page' : ''}.',
        );
        await Future.wait([
          adb.stream(adb.rootShell(webuiLogScript(id), recovery: false)),
          if (boolArg('page')) adb.stream(kPageLogcat),
        ]);
      case null:
        throwToolExit('No adb device.');
      default:
        throwToolExit('The device is in "$state" state.');
    }
    return FlutterCommandResult.success();
  }
}
