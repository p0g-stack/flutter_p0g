import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../artifact_cache.dart';
import '../artifact_lock.dart';
import '../aera/kit.dart';
import '../frb/frb.dart';
import '../squadron.dart';
import '../webui/dart_android.dart';
import '../webui/app_plane.dart';
import '../webui/flutter_webui.dart';

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
        help:
            "The repository's flutter_webui and *_webui packages resolved, "
            'and the patched web SDK with its fallback fonts.',
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
      ..addFlag('app-plane', help: 'The webui-termux-api APK the app plane ships (pinned).');
  }

  @override
  final name = 'precache';

  @override
  final description = 'Download or build the artifacts p0g targets need.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final androidSource = stringArg('dart-android-kit');
    final androidHash = stringArg('dart-android-sha256');
    final androidAbis = stringsArg('dart-android-abi');
    final aeraSource = stringArg('aera-kit');
    final aeraHash = stringArg('aera-kit-sha256');
    validateKitSelection(androidSource, androidHash, androidAbis.length);
    validateKitSelection(aeraSource, aeraHash, 1);
    if (androidHash != null && androidSource == null && !boolArg('dart-android')) {
      throwToolExit('--dart-android-sha256 requires --dart-android or --dart-android-kit.');
    }
    if (aeraHash != null && aeraSource == null && !boolArg('aera')) {
      throwToolExit('--aera-kit-sha256 requires --aera or --aera-kit.');
    }
    if (androidSource == null && boolArg('dart-android')) {
      final version = sdkDartVersion();
      final lock = await artifactLock();
      for (final abi in androidAbis) {
        lock.dartAndroidKit(version, abi);
      }
    }
    if (aeraSource == null && boolArg('aera')) {
      (await artifactLock()).aeraKit(
        globals.flutterVersion.frameworkVersion,
        'linux-arm64-${stringArg('aera-mode')!}',
      );
    }
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
        for (final abi in androidAbis) {
          await precacheDartAndroid(abi: abi, sha256Hex: androidHash);
        }
      }
    }
    if (stringArg('aera-kit') case final kit?) {
      await precacheAeraKit(kit, sha256Hex: stringArg('aera-kit-sha256'));
    } else if (boolArg('aera')) {
      await precacheAeraKit(null, sha256Hex: aeraHash, mode: stringArg('aera-mode')!);
    }
    if (boolArg('app-plane')) await precacheAppPlane(force: true);
    return FlutterCommandResult.success();
  }
}

/// Rejects missing, malformed or ambiguous digests before precache does I/O.
void validateKitSelection(String? source, String? digest, int defaultTargets) {
  if (source != null || digest != null) requireKitSha256(digest);
  if (source == null && digest != null && defaultTargets != 1) {
    throwToolExit('A kit sha256 without a source requires exactly one default target.');
  }
}
