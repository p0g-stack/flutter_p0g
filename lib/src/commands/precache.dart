import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../frb/frb.dart';

/// Fetches or builds what the p0g targets need beyond stock Flutter.
class PrecacheCommand extends FlutterCommand {
  PrecacheCommand() {
    argParser
      ..addFlag(
        'web',
        defaultsTo: true,
        help: "Flutter's web SDK (stock until flutter-webui releases patched web_ui).",
      )
      ..addFlag(
        'frb',
        help: 'Build flutter_rust_bridge with the patches in patches/frb (needs git and cargo).',
      )
      ..addFlag('aera', help: 'AERA engine and runtime kits (not released yet).')
      ..addFlag('app-plane', help: 'The webui-termux-api APK (not released yet).');
  }

  @override
  final name = 'precache';

  @override
  final description = 'Download or build the artifacts p0g targets need.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (boolArg('web')) {
      await globals.cache.updateAll({DevelopmentArtifact.web, DevelopmentArtifact.universal});
    }
    if (boolArg('frb')) await precacheFrb();
    if (boolArg('aera')) globals.printWarning('AERA kits: no release yet (flutter-aera CI).');
    if (boolArg('app-plane')) globals.printWarning('webui-termux-api: no release yet.');
    return FlutterCommandResult.success();
  }
}
