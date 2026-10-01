import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import '../p0g_cache.dart';

/// flutter-aera's runtime kit for one target and build mode: the payload
/// tree every plugin carries (launcher, embedder, engine, loader, glibc,
/// Mesa, ICU data, CA bundle), plus the host `gen_snapshot` matching that
/// engine for profile and release builds. Archive layout:
///
/// ```
/// VERSION          engine revision (must equal the pinned Flutter's)
/// TARGET           e.g. linux-arm64
/// MODE             debug | profile | release
/// payload/...      tree expanded at AERA_PLUGIN_ROOT
/// host/gen_snapshot  (profile, release)
/// ```
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

/// Checks a kit archive; returns why it can't be used, or null.
@visibleForTesting
String? validateAeraKit(Archive archive, String engineRevision) {
  String? text(String name) {
    final f = archive.findFile(name);
    return f == null ? null : String.fromCharCodes(f.content as List<int>).trim();
  }

  final version = text('VERSION');
  final target = text('TARGET');
  final mode = text('MODE');
  if (version == null || target == null || mode == null) return 'kit lacks VERSION, TARGET or MODE';
  if (version != engineRevision) {
    return 'kit is for engine $version, this Flutter uses $engineRevision';
  }
  if (!const {'debug', 'profile', 'release'}.contains(mode)) return 'unknown MODE $mode';
  if (archive.findFile('payload/usr/bin/aera-plugin') == null) {
    return 'kit lacks payload/usr/bin/aera-plugin';
  }
  if (mode != 'debug' && archive.findFile('host/gen_snapshot') == null) {
    return '$mode kit lacks host/gen_snapshot';
  }
  return null;
}

/// Installs a kit `.tar.gz` (path or https URL) under its TARGET and MODE.
Future<void> precacheAeraKit(String source, {String? sha256Hex}) async {
  final bytes = await fetchBytes(source);
  final digest = sha256.convert(bytes).toString();
  if (sha256Hex != null && digest != sha256Hex) {
    throwToolExit('Kit sha256 is $digest, expected $sha256Hex.');
  }
  final archive = decodeTarGz(bytes);
  final problem = validateAeraKit(archive, engineRevision());
  if (problem != null) throwToolExit('AERA kit: $problem.');
  String text(String n) => String.fromCharCodes(archive.findFile(n)!.content as List<int>).trim();
  final kit = AeraKit.forTarget(text('TARGET'), text('MODE'));
  if (kit.dir.existsSync()) kit.dir.deleteSync(recursive: true);
  for (final f in archive.files.where((f) => f.isFile)) {
    final out = kit.dir.childFile(f.name)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(f.content as List<int>);
    if (f.mode & 0x49 != 0) globals.os.chmod(out, '755');
  }
  globals.printStatus('AERA kit ${text('TARGET')}-${text('MODE')} installed (sha256 $digest).');
}
