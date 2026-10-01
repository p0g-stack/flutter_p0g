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

/// Module directories flutter_p0g fills with programs of its own: the root
/// channel (flutter-webui) and the app plane (webui-packages).
const kToolProgramDirs = ['flutter_webui', 'webui_app_plane'];

/// Files run as programs: scripts at the module root and anything in bin/
/// or the tool's program directories.
bool isExecutableModulePath(String path) =>
    path.startsWith('bin/') ||
    kToolProgramDirs.any((d) => path.startsWith('$d/')) ||
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
    if (!isPrunedWebFile(path, wasm: wasm) && !isSigningSecret(path)) {
      files['webroot/$path'] = bytes;
    }
  });
  webuiFolder.forEach((path, bytes) {
    if (isSigningSecret(path)) return;
    if (_expandsVars(path)) {
      final text = utf8.decode(bytes);
      bytes = utf8.encode(expandBuildVars(text, buildName: buildName, buildNumber: buildNumber));
    }
    files[path] = bytes;
  });
  files.addAll(extra);
  final permDirs = [
    for (final d in kToolProgramDirs)
      if (files.keys.any((f) => f.startsWith('$d/'))) d,
  ];
  if (permDirs.isNotEmpty) {
    final own = files['customize.sh'] == null ? '' : utf8.decode(files['customize.sh']!);
    files['customize.sh'] = utf8.encode(withToolPerms(own, permDirs));
  }
  final moduleId = files['module.prop'] == null
      ? null
      : readProp(utf8.decode(files['module.prop']!), 'id');
  if (moduleId != null) {
    final own = files['customize.sh'] == null ? '' : utf8.decode(files['customize.sh']!);
    files['customize.sh'] = utf8.encode(withDataFolder(own, moduleId));
    final ownUninstall = files['uninstall.sh'] == null ? '' : utf8.decode(files['uninstall.sh']!);
    files['uninstall.sh'] = utf8.encode(withUninstall(ownUninstall));
  }
  if (files.keys.any((f) => f.startsWith('system/product/app/WebuiApi_'))) {
    final own = files['customize.sh'] == null ? '' : utf8.decode(files['customize.sh']!);
    files['customize.sh'] = utf8.encode(withMetamoduleNotice(own));
  }
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

/// Signing material that must never ship in a module zip: `key.properties`
/// and keystores, wherever they sit in the tree.
bool isSigningSecret(String path) {
  final name = path.split('/').last.toLowerCase();
  return name == 'key.properties' ||
      name.endsWith('.jks') ||
      name.endsWith('.keystore') ||
      name.endsWith('.p12') ||
      name.endsWith('.pfx');
}

/// [customizeSh] with a block that makes the tool's program directories
/// executable: managers install with 0644 files and leave the rest to
/// `customize.sh`.
String withToolPerms(String customizeSh, List<String> dirs) {
  final b = StringBuffer(customizeSh);
  if (customizeSh.isNotEmpty && !customizeSh.endsWith('\n')) b.writeln();
  b.writeln('# flutter_p0g: the programs it ships (generated at build).');
  for (final d in dirs) {
    b.writeln('set_perm_recursive "\$MODPATH/$d" 0 0 0755 0755');
  }
  return b.toString();
}

/// The persist.config key customize.sh sets on install (KernelSU's
/// `ksud module config`, cleared by ksud on uninstall).
const kInstallMarkerKey = 'webui.installed';

/// [customizeSh] with the data folder's install step (app-plane-picture.md
/// section 8): a fresh install (no `/data/adb/modules/<id>` yet) wipes a
/// leftover `/data/adb/<id>`, an update keeps it; both set the install
/// marker in persist.config.
String withDataFolder(String customizeSh, String moduleId) {
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]+$').hasMatch(moduleId)) {
    throw StateError('module.prop id "$moduleId" is not a valid module id');
  }
  final b = StringBuffer(customizeSh);
  if (customizeSh.isNotEmpty && !customizeSh.endsWith('\n')) b.writeln();
  b
    ..writeln('# flutter_p0g: the data folder /data/adb/$moduleId (generated at build).')
    ..writeln('[ -d /data/adb/modules/$moduleId ] || rm -rf /data/adb/$moduleId')
    ..writeln(
      'KSU_MODULE=$moduleId /data/adb/ksud module config set $kInstallMarkerKey 1 ||'
      ' ui_print "! ksud module config failed: KernelSU 3.0+ or KernelSU Next 3.0+ is needed"',
    );
  return b.toString();
}

/// The install-time check: KernelSU 3.x (and KernelSU Next 3.x, which sets
/// the same variables) mounts a module's `system/` only through a
/// metamodule, so without one the module's app never appears. `|| true`
/// keeps the line's status 0 when there is nothing to say.
const kMetamoduleCheck =
    r'[ "$KSU" = true ] && [ "${KSU_VER%%.*}" -ge 3 ] 2>/dev/null && '
    r'[ ! -e /data/adb/metamodule ] && '
    r'ui_print "! No metamodule installed: this module'
    "'"
    's app needs one to be mounted (KernelSU 3.x)" || true';

/// [customizeSh] followed by [kMetamoduleCheck].
String withMetamoduleNotice(String customizeSh) {
  final b = StringBuffer(customizeSh);
  if (customizeSh.isNotEmpty && !customizeSh.endsWith('\n')) b.writeln();
  b
    ..writeln(
      '# flutter_p0g: the app plane needs a metamodule on KernelSU 3.x (generated at build).',
    )
    ..writeln(kMetamoduleCheck);
  return b.toString();
}

/// The fixed uninstall line: frees `/data/adb/<id>` after a final uninstall.
const kUninstallLine = r'MODPATH=${0%/*}; rm -rf "/data/adb/${MODPATH##*/}"';

/// [uninstallSh] (the app's own, if any) followed by [kUninstallLine].
String withUninstall(String uninstallSh) {
  final b = StringBuffer(uninstallSh.isEmpty ? '#!/system/bin/sh\n' : uninstallSh);
  if (uninstallSh.isNotEmpty && !uninstallSh.endsWith('\n')) b.writeln();
  b
    ..writeln('# flutter_p0g: free the data folder (generated at build).')
    ..writeln(kUninstallLine);
  return b.toString();
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

/// The update file managers poll: `updateJson` in module.prop names it
/// (KernelSU, APatch and Magisk share the format).
const kUpdateJsonName = 'update.json';
const kChangelogName = 'changelog.md';

/// Where a GitHub-hosted app's latest release serves its assets, from the
/// pubspec's `repository:` (null for anything else).
String? githubReleaseBase(String? repository) {
  final m = RegExp(r'^https://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?/?$')
      .firstMatch(repository?.trim() ?? '');
  return m == null ? null : 'https://github.com/${m[1]}/${m[2]}/releases/latest/download/';
}

/// [moduleProp] with `updateJson=[url]`, replacing one already there.
String withUpdateJson(String moduleProp, String url) {
  final lines = [
    for (final line in moduleProp.split('\n'))
      if (!RegExp(r'^\s*updateJson\s*=').hasMatch(line)) line,
  ];
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return '${[...lines, 'updateJson=$url'].join('\n')}\n';
}

/// The update file for a release whose assets sit under [base] (the
/// directory of `updateJson`, ending in `/`).
String updateJsonFor({
  required String base,
  required String version,
  required String versionCode,
  required String zipName,
}) {
  final code = int.tryParse(versionCode);
  if (code == null) throw FormatException('versionCode "$versionCode" is not a number');
  return '${const JsonEncoder.withIndent('  ').convert({'version': version, 'versionCode': code, 'zipUrl': '$base$zipName', 'changelog': '$base$kChangelogName'})}\n';
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
