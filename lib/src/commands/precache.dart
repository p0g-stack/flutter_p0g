import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../aera/kit.dart';
import '../frb/frb.dart';
import '../squadron.dart';
import '../webui/dart_android.dart';
import '../webui/app_plane.dart';
import '../webui/flutter_webui.dart';
import '../webui/webui_packages.dart';

/// Fetches or builds what the p0g targets need beyond stock Flutter.
class PrecacheCommand extends FlutterCommand {
  PrecacheCommand() {
    argParser
      ..addFlag(
        'web',
        defaultsTo: true,
        help: "Flutter's stock web SDK (the base the patched one is built from).",
      )
      ..addFlag(
        'webui',
        defaultsTo: true,
        help: 'flutter-webui at its pin: the bootstrap and the patched web SDK.',
      )
      ..addFlag(
        'frb',
        help: 'Build flutter_rust_bridge with the patches in patches/frb (needs git and cargo).',
      )
      ..addFlag(
        'squadron',
        help:
            "This project's patched Squadron: squadron_process's patch series, "
            'materialized and pointed at by pubspec_overrides.yaml, then pub get.',
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
      ..addFlag('aera', help: "flutter-aera's released runtime kit for --aera-mode.")
      ..addOption('aera-mode', allowed: ['debug', 'profile', 'release'], defaultsTo: 'debug')
      ..addOption(
        'aera-kit',
        help: 'Install a flutter-aera runtime kit (.tar.xz or .tar.gz, path or https URL).',
      )
      ..addOption('aera-kit-sha256', help: 'Expected sha256 of the AERA kit archive.')
      ..addFlag('webui-packages', help: 'webui-packages (the *_webui plugins and the app plane).')
      ..addFlag('app-plane', help: 'The webui-termux-api APK the app plane ships (pinned).');
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
    if (boolArg('webui')) await precacheFlutterWebui(force: argResults!.wasParsed('webui'));
    if (boolArg('frb')) await precacheFrb();
    if (boolArg('squadron')) {
      await ensurePatchedSquadron(globals.fs.currentDirectory, force: true);
    }
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
    } else if (boolArg('aera')) {
      await precacheAeraKit(
        aeraKitUrl(globals.flutterVersion.frameworkVersion, stringArg('aera-mode')!),
      );
    }
    if (boolArg('webui-packages')) await precacheWebuiPackages(force: true);
    if (boolArg('app-plane')) await precacheAppPlane(force: true);
    return FlutterCommandResult.success();
  }
}
