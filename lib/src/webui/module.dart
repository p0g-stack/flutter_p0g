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
  AppPlaneApp? appPlane,
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
  String own(String name) => files[name] == null ? '' : utf8.decode(files[name]!);
  if (appPlane != null) {
    files[kAppPlaneInstallScript] = utf8.encode(appPlaneInstallScript(appPlane));
    files['customize.sh'] = utf8.encode(withAppPlaneInstall(own('customize.sh')));
    files['service.sh'] = utf8.encode(withAppPlaneReinstall(own('service.sh')));
    files['uninstall.sh'] = utf8.encode(withAppPlaneUninstall(own('uninstall.sh'), appPlane));
  }
  // The app's own system/ files, if any: KernelSU 3.x mounts them only
  // through a metamodule.
  if (files.keys.any((f) => f.startsWith('system/'))) {
    files['customize.sh'] = utf8.encode(withMetamoduleNotice(own('customize.sh')));
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
/// metamodule, so without one the module's system files never appear. `|| true`
/// keeps the line's status 0 when there is nothing to say.
const kMetamoduleCheck =
    r'[ "$KSU" = true ] && [ "${KSU_VER%%.*}" -ge 3 ] 2>/dev/null && '
    r'[ ! -e /data/adb/metamodule ] && '
    r'ui_print "! No metamodule installed: this module'
    "'"
    's system/ files need one to be mounted (KernelSU 3.x)" || true';

/// [customizeSh] followed by [kMetamoduleCheck].
String withMetamoduleNotice(String customizeSh) {
  final b = StringBuffer(customizeSh);
  if (customizeSh.isNotEmpty && !customizeSh.endsWith('\n')) b.writeln();
  b
    ..writeln('# flutter_p0g: system/ needs a metamodule on KernelSU 3.x (generated at build).')
    ..writeln(kMetamoduleCheck);
  return b.toString();
}

/// The module's app plane app: installed as an ordinary app, not mounted,
/// so KernelSU's "Umount modules" cannot take its APK away
/// (flutter_p0g issue "App plane: install method"; webui-packages
/// docs/plugins.md).
typedef AppPlaneApp = ({String package, int versionCode});

/// The app plane APK in the module, a payload the install script reads.
const kAppPlaneApkPath = 'webui_app_plane/app.apk';

/// The generated script that installs [kAppPlaneApkPath].
const kAppPlaneInstallScript = 'webui_app_plane/app-install.sh';

/// Installs the module's app with a PackageInstaller session as the Play
/// Store (`-i com.android.vending`), as j-hc/revanced-magisk-module does.
/// Skips when [app] at its version is already there; `--if-missing`
/// installs only when the app is gone. Prints what it did; exits 1 on
/// failure. After the install, `after_install` applies the two device
/// settings Termux:API's own main screen asks for (draw over other apps,
/// battery optimization off), both best effort.
String appPlaneInstallScript(AppPlaneApp app) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]*$').hasMatch(app.package)) {
    throw StateError('"${app.package}" is not a package name');
  }
  return '''
#!/system/bin/sh
# flutter_p0g: installs this module's app plane app (generated at build).
# Usage: sh app-install.sh [--if-missing]
PKG=${app.package}
VC=${app.versionCode}
APK=\${0%/*}/app.apk

case "\$(pm path \$PKG 2>/dev/null </dev/null)" in
  package:*)
    [ "\$1" = --if-missing ] && exit 0
    v=\$(dumpsys package \$PKG 2>/dev/null | grep -m1 versionCode=)
    v=\${v#*versionCode=}; v=\${v%% *}
    if [ "\$v" = "\$VC" ]; then echo "\$PKG \$VC is installed"; exit 0; fi ;;
esac

after_install() {
  # The two settings Termux:API's own main screen (TermuxAPIMainActivity)
  # asks the user for, best effort: draw over other apps, so an activity
  # started from a broadcast (Share's chooser, dialogs) is not blocked as a
  # background activity start (devicelab, Android 15); battery optimization
  # off, "so that termux-api script can start it from the background".
  appops set "\$PKG" SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1
  dumpsys deviceidle whitelist +"\$PKG" >/dev/null 2>&1
}

T=/data/local/tmp/webui-app-plane-\$PKG.apk
cp -f "\$APK" "\$T" && chmod 644 "\$T" && chown 1000:1000 "\$T"
chcon u:object_r:apk_data_file:s0 "\$T" 2>/dev/null
SZ=\$(stat -c %s "\$T")
O=\$(pm install-create --user 0 -i com.android.vending -r -S "\$SZ" 2>&1 </dev/null)
case "\$O" in
  *'['*']'*)
    S=\${O#*[}; S=\${S%%]*}
    O=\$(pm install-write -S "\$SZ" "\$S" base.apk "\$T" 2>&1 </dev/null)
    case "\$O" in
      *Success*) O=\$(pm install-commit "\$S" 2>&1 </dev/null) ;;
      *) pm install-abandon "\$S" >/dev/null 2>&1 </dev/null ;;
    esac ;;
esac
after_install
rm -f "\$T"

case "\$O" in
  *Success*) echo "Installed \$PKG \$VC" ;;
  *)
    echo "! Installing \$PKG failed: \$O"
    case "\$O" in
      *UPDATE_INCOMPATIBLE*) echo "! It is signed with another key: uninstall \$PKG, then install the module again" ;;
    esac
    exit 1 ;;
esac
''';
}

/// [customizeSh] followed by the app plane install (on install and update).
String withAppPlaneInstall(String customizeSh) {
  final b = StringBuffer(customizeSh);
  if (customizeSh.isNotEmpty && !customizeSh.endsWith('\n')) b.writeln();
  b
    ..writeln('# flutter_p0g: install or update the app plane app (generated at build).')
    ..writeln(
      'sh "\$MODPATH/$kAppPlaneInstallScript" 2>&1 | while IFS= read -r l; do ui_print "  \$l"; done',
    );
  return b.toString();
}

/// [serviceSh] followed by a reinstall once booted, only if the user removed
/// the app.
String withAppPlaneReinstall(String serviceSh) {
  final b = StringBuffer(serviceSh.isEmpty ? '#!/system/bin/sh\n' : serviceSh);
  if (serviceSh.isNotEmpty && !serviceSh.endsWith('\n')) b.writeln();
  b
    ..writeln('# flutter_p0g: reinstall the app plane app if it was removed (generated at build).')
    ..writeln(
      '(MODDIR=\${0%/*}; until [ "\$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done; '
      'sh "\$MODDIR/$kAppPlaneInstallScript" --if-missing '
      '>"\$MODDIR/webui_app_plane/app-install.log" 2>&1) &',
    );
  return b.toString();
}

/// [uninstallSh] with the app plane app removed once the package manager
/// runs (managers run uninstall.sh early in boot).
String withAppPlaneUninstall(String uninstallSh, AppPlaneApp app) {
  final b = StringBuffer(uninstallSh.isEmpty ? '#!/system/bin/sh\n' : uninstallSh);
  if (uninstallSh.isNotEmpty && !uninstallSh.endsWith('\n')) b.writeln();
  b
    ..writeln('# flutter_p0g: remove the app plane app (generated at build).')
    ..writeln(
      'nohup sh -c \'until [ "\$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done; '
      'pm uninstall ${app.package}\' >/dev/null 2>&1 &',
    );
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
