import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../templates.dart';

/// One file of the module zip.
class ModuleFile {
  ModuleFile(this.path, this.bytes, {this.executable = false});

  /// Posix path inside the zip.
  final String path;
  final List<int> bytes;
  final bool executable;
}

/// Parts of `flutter build web` output that never load in a manager's
/// WebView: debug symbols, the experimental text stacks, the service worker
/// (no host runs one), the build stamp, and Skwasm unless built `--wasm`.
bool isPrunedWebFile(String relPath, {bool wasm = false}) {
  final path = p.posix.normalize(relPath.replaceAll(r'\', '/'));
  if (path == 'flutter_service_worker.js' || path == '.last_build_id') return true;
  if (!path.startsWith('canvaskit/')) return false;
  if (!wasm && p.posix.basename(path).startsWith('skwasm')) return true;
  return path.endsWith('.symbols') ||
      path.startsWith('canvaskit/webparagraph/') ||
      p.posix.basename(path).startsWith('wimp.');
}

/// Files run as programs: scripts at the module root and anything in bin/.
bool isExecutableModulePath(String path) =>
    path.startsWith('bin/') ||
    (!path.contains('/') && path.endsWith('.sh')) ||
    path == 'META-INF/com/google/android/update-binary';

/// Assembles the module: web build in `webroot/`, then `webui/` on top
/// (its `webroot/` overlays the build), then extra files (the CLI and its
/// libraries), then the Magisk stub. Later entries win.
List<ModuleFile> assembleModule({
  required Map<String, List<int>> webBuild,
  required Map<String, List<int>> webuiFolder,
  Map<String, List<int>> extra = const {},
  required String buildName,
  required String buildNumber,
  bool wasm = false,
}) {
  final files = <String, List<int>>{};
  webBuild.forEach((path, bytes) {
    if (!isPrunedWebFile(path, wasm: wasm)) files['webroot/$path'] = bytes;
  });
  webuiFolder.forEach((path, bytes) {
    if (_expandsVars(path)) {
      final text = utf8.decode(bytes);
      bytes = utf8.encode(expandBuildVars(text, buildName: buildName, buildNumber: buildNumber));
    }
    files[path] = bytes;
  });
  files.addAll(extra);
  files['META-INF/com/google/android/update-binary'] = utf8.encode(kUpdateBinary);
  files['META-INF/com/google/android/updater-script'] = utf8.encode(kUpdaterScript);
  if (!files.containsKey('module.prop')) {
    throw StateError('webui/module.prop is missing; run `flutter_p0g create .`');
  }
  final paths = files.keys.toList()..sort();
  return [
    for (final path in paths)
      ModuleFile(path, files[path]!, executable: isExecutableModulePath(path)),
  ];
}

bool _expandsVars(String path) => path == 'module.prop' || path == 'webroot/config.json';

/// Reads a key from module.prop text.
String? readProp(String moduleProp, String key) {
  for (final line in moduleProp.split('\n')) {
    final i = line.indexOf('=');
    if (i > 0 && line.substring(0, i).trim() == key) return line.substring(i + 1).trim();
  }
  return null;
}

/// Zips the module with unix modes, module.prop first like the stock ones.
Uint8List zipModule(List<ModuleFile> files) {
  final archive = Archive();
  final ordered = [
    ...files.where((f) => f.path == 'module.prop'),
    ...files.where((f) => f.path != 'module.prop'),
  ];
  for (final f in ordered) {
    final entry = ArchiveFile(f.path, f.bytes.length, f.bytes)
      ..mode = f.executable ? 0x81ed /* 0100755 */ : 0x81a4 /* 0100644 */;
    archive.addFile(entry);
  }
  return markMadeByUnix(Uint8List.fromList(ZipEncoder().encode(archive)!));
}

/// package:archive writes "made by MS-DOS", so unzip ignores the modes. Mark
/// every central directory entry as made by Unix (3) so they apply.
Uint8List markMadeByUnix(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final eocd = zip.length - 22; // no archive comment is written
  if (data.getUint32(eocd, Endian.little) != 0x06054b50) {
    throw StateError('unexpected zip layout');
  }
  final count = data.getUint16(eocd + 10, Endian.little);
  var at = data.getUint32(eocd + 16, Endian.little);
  for (var i = 0; i < count; i++) {
    if (data.getUint32(at, Endian.little) != 0x02014b50) {
      throw StateError('bad central directory entry $i');
    }
    zip[at + 5] = 3;
    at +=
        46 +
        data.getUint16(at + 28, Endian.little) +
        data.getUint16(at + 30, Endian.little) +
        data.getUint16(at + 32, Endian.little);
  }
  return zip;
}
