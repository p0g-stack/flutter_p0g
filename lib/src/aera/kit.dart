import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

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

  bool get isInstalled =>
      payload.childDirectory('usr').childDirectory('bin').childFile('aera-plugin').existsSync();

  static AeraKit forTarget(String target, String mode) =>
      AeraKit(p0gCacheDir().childDirectory('aera-kit').childDirectory('$target-$mode'));
}

/// The release kit for [mode] at the pinned Flutter [flutterVersion].
String aeraKitUrl(String flutterVersion, String mode) =>
    'https://github.com/p0g-stack/flutter-aera/releases/download/kit-$flutterVersion/'
    'flutter-aera-kit-linux-arm64-$mode-$flutterVersion.tar.xz';

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
  if (json['arch'] is! String) return 'kit.json lacks arch';
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

/// Installs a kit `.tar.xz` (or `.tar.gz`) from a path or https URL. A
/// release URL's `.sha256` sibling is checked when [sha256Hex] isn't given.
Future<void> precacheAeraKit(String source, {String? sha256Hex}) async {
  final bytes = await fetchBytes(source);
  if (sha256Hex == null && source.startsWith('https://')) {
    sha256Hex = utf8.decode(await fetchBytes('$source.sha256')).trim().split(RegExp(r'\s+')).first;
  }
  final digest = sha256.convert(bytes).toString();
  if (sha256Hex != null && digest != sha256Hex) {
    throwToolExit('Kit sha256 is $digest, expected $sha256Hex.');
  }
  final archive = source.endsWith('.gz') ? decodeTarGz(bytes) : decodeTar(await _unxz(bytes));
  final problem = validateAeraKit(archive, engineRevision());
  if (problem != null) throwToolExit('AERA kit: $problem.');
  final kit = AeraKit.forTarget(kitTarget(archive), kitMode(archive));
  if (kit.dir.existsSync()) kit.dir.deleteSync(recursive: true);
  for (final f in archive.files) {
    final File out = isKitMetadata(f.name)
        ? kit.dir.childFile(f.name)
        : kit.payload.childFile(f.name);
    out
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(f.content as List<int>);
    if (f.mode & 0x49 != 0) globals.os.chmod(out, '755');
  }
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
