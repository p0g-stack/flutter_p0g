import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../aera/kit.dart';
import '../frb/frb.dart';
import '../webui/dart_android.dart';

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
      ..addFlag(
        'dart-android',
        help: 'The Android Dart kit (host gen_snapshot + device dartaotruntime) for cli/.',
      )
      ..addOption('dart-android-kit', help: 'Kit .tar.gz path or https URL (default: the release).')
      ..addOption('dart-android-sha256', help: 'Expected sha256 of the kit archive.')
      ..addMultiOption(
        'dart-android-abi',
        allowed: kDartArchForAbi.keys,
        defaultsTo: [kDefaultAbi],
        help: 'Device ABIs to fetch release kits for (x86_64 for emulators).',
      )
      ..addOption(
        'aera-kit',
        help: 'Install a flutter-aera runtime kit .tar.gz (path or https URL).',
      )
      ..addOption('aera-kit-sha256', help: 'Expected sha256 of the AERA kit archive.')
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
    if (boolArg('dart-android') || argResults!.wasParsed('dart-android-kit')) {
      if (stringArg('dart-android-kit') case final kit?) {
        await precacheDartAndroid(source: kit, sha256Hex: stringArg('dart-android-sha256'));
      } else {
        for (final abi in stringsArg('dart-android-abi')) {
          await precacheDartAndroid(abi: abi);
        }
      }
    }
    if (stringArg('aera-kit') case final kit?) {
      await precacheAeraKit(kit, sha256Hex: stringArg('aera-kit-sha256'));
    }
    if (boolArg('app-plane')) globals.printWarning('webui-termux-api: no release yet.');
    return FlutterCommandResult.success();
  }
}
