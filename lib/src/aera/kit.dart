import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import '../artifact_cache.dart';
import '../artifact_pins.dart';
import '../p0g_cache.dart';

/// flutter-aera's runtime kit for one arch and build mode (flutter-aera
/// `spec/aerap.md`, "Runtime kit"): the payload tree every plugin carries
/// (launcher, embedder, engine, glibc and its loader, Mesa, Vulkan, ICU
/// data, CA bundle), plus `kit.json` with the pins, which is not packed.
/// Profile and release kits also need `host/gen_snapshot` for the engine,
/// which is not packed either.
class AeraKit {
  AeraKit(this.dir);

  final Directory dir;

  Directory get payload => dir.childDirectory('payload');
  File get genSnapshot => dir.childDirectory('host').childFile('gen_snapshot');

  bool get isInstalled {
    if (!payload
        .childDirectory('usr')
        .childDirectory('bin')
        .childFile('aera-plugin')
        .existsSync()) {
      return false;
    }
    final identity = readKitIdentity(dir);
    final meta = dir.childFile('kit.json');
    if (identity == null || !meta.existsSync()) return false;
    try {
      final json = jsonDecode(meta.readAsStringSync());
      return json is Map &&
          json['kit'] == 1 &&
          identity['version'] == json['flutter'] &&
          identity['engine'] == engineRevision() &&
          identity['engine'] == json['engine_revision'] &&
          identity['target'] == 'linux-${json['arch']}' &&
          identity['mode'] == json['mode'] &&
          dir.basename == '${identity['target']}-${identity['mode']}' &&
          (json['mode'] == 'debug' || genSnapshot.existsSync());
    } on FormatException {
      return false;
    }
  }

  static AeraKit forTarget(String target, String mode) =>
      AeraKit(p0gCacheDir().childDirectory('aera-kit').childDirectory('$target-$mode'));
}

/// The pinned release URL for the exact Flutter version, target and mode.
String aeraKitUrl(String flutterVersion, String mode, {String target = 'linux-arm64'}) =>
    pinnedKit(aeraKitPins, 'AERA', flutterVersion, '$target-$mode').url;

/// Members that stay out of the payload.
@visibleForTesting
bool isKitMetadata(String name) => name == 'kit.json' || name.startsWith('host/');

/// Checks a kit archive against the pinned engine; returns why it can't be
/// used, or null.
@visibleForTesting
String? validateAeraKit(Archive archive, String engineRevision) {
  final meta = archive.findFile('kit.json');
  if (meta == null) return 'kit lacks kit.json';
  final Map<String, Object?> json;
  try {
    json = jsonDecode(utf8.decode(meta.content as List<int>)) as Map<String, Object?>;
  } on FormatException catch (e) {
    return 'kit.json: ${e.message}';
  }
  if (json['kit'] != 1) return 'kit.json format ${json['kit']} is not 1';
  if (json['engine_revision'] != engineRevision) {
    return 'kit is for engine ${json['engine_revision']}, this Flutter uses $engineRevision';
  }
  final mode = json['mode'];
  if (!const {'debug', 'profile', 'release'}.contains(mode)) return 'unknown mode $mode';
  if (!const {'arm64', 'x64'}.contains(json['arch'])) return 'unknown arch ${json['arch']}';
  if (json['flutter'] is! String) return 'kit.json lacks flutter';
  if (archive.findFile('usr/bin/aera-plugin') == null) return 'kit lacks usr/bin/aera-plugin';
  if (mode != 'debug' && archive.findFile('host/gen_snapshot') == null) {
    return '$mode kit lacks host/gen_snapshot';
  }
  return null;
}

/// `linux-<arch>` from kit.json's arch.
String kitTarget(Archive archive) {
  final json = jsonDecode(utf8.decode(archive.findFile('kit.json')!.content as List<int>)) as Map;
  return 'linux-${json['arch']}';
}

String kitMode(Archive archive) =>
    (jsonDecode(utf8.decode(archive.findFile('kit.json')!.content as List<int>)) as Map)['mode']
        as String;

/// Installs a verified kit archive without replacing a working kit on failure.
///
/// An explicit [source] requires [sha256Hex]. A null source selects the
/// committed pin for [target] and [mode].
Future<void> precacheAeraKit(
  String? source, {
  String? sha256Hex,
  String target = 'linux-arm64',
  String mode = 'debug',
}) async {
  final explicit = source != null;
  if (explicit || sha256Hex != null) sha256Hex = requireKitSha256(sha256Hex);
  final version = globals.flutterVersion.frameworkVersion;
  if (!explicit) {
    final pin = pinnedKit(aeraKitPins, 'AERA', version, '$target-$mode');
    source = pin.url;
    sha256Hex ??= pin.sha256;
  }
  final expected = requireKitSha256(sha256Hex);
  final existing = AeraKit.forTarget(target, mode);
  if (!explicit && existing.isInstalled && readKitIdentity(existing.dir)?['sha256'] == expected) {
    globals.printStatus('AERA kit $target-$mode: up to date.');
    return;
  }
  final bytes = await fetchBytes(source!);
  final digest = sha256.convert(bytes).toString();
  if (digest != expected) throwToolExit('Kit sha256 is $digest, expected $expected.');
  // Asset-ID URLs have no filename; identify gzip by its magic bytes.
  final archive = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
      ? decodeTarGz(bytes)
      : decodeTar(await _unxz(bytes));
  final engine = engineRevision();
  final problem = validateAeraKit(archive, engine);
  if (problem != null) throwToolExit('AERA kit: $problem.');
  final json = jsonDecode(utf8.decode(archive.findFile('kit.json')!.content as List<int>)) as Map;
  if (json['flutter'] != version) {
    throwToolExit('AERA kit: expected Flutter $version, got ${json['flutter']}.');
  }
  if (!explicit && (kitTarget(archive) != target || kitMode(archive) != mode)) {
    throwToolExit(
      'AERA kit: expected $target-$mode, got ${kitTarget(archive)}-${kitMode(archive)}.',
    );
  }
  final kit = AeraKit.forTarget(kitTarget(archive), kitMode(archive));
  installKitStaged(
    kit.dir,
    {
      'sha256': digest,
      'version': version,
      'engine': engine,
      'target': kitTarget(archive),
      'mode': kitMode(archive),
    },
    (stage) {
      for (final f in archive.files) {
        final root = isKitMetadata(f.name) ? stage : stage.childDirectory('payload');
        final out = kitMemberFile(root, f.name);
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(f.content as List<int>);
        if (f.mode & 0x49 != 0) globals.os.chmod(out, '755');
      }
    },
  );
  globals.printStatus(
    'AERA kit ${kitTarget(archive)}-${kitMode(archive)} installed (sha256 $digest).',
  );
}

/// xz via XZ Utils (already needed to pack runtime.xz).
Future<List<int>> _unxz(List<int> bytes) async {
  final tmp = globals.fs.systemTempDirectory.createTempSync('aera_kit');
  try {
    final xz = tmp.childFile('kit.tar.xz')..writeAsBytesSync(bytes);
    final r = await globals.processUtils.run(['xz', '-d', '-k', xz.path]);
    if (r.exitCode != 0) throwToolExit('xz -d failed:\n$r');
    return tmp.childFile('kit.tar').readAsBytesSync();
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
