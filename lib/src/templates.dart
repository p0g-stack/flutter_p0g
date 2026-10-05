/// The platform folders `flutter_p0g create` adds, as `flutter create
/// --platforms` adds `linux/` or `web/`. Kept as strings so the tool needs no
/// asset lookup once activated.
library;

import 'dart:convert';

/// Substituted at build time from the pubspec version, the way Xcode's
/// Info.plist uses `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`.
const kBuildNameVar = r'$(FLUTTER_BUILD_NAME)';
const kBuildNumberVar = r'$(FLUTTER_BUILD_NUMBER)';

/// The module icon `module.prop` names: the web build's maskable icon.
const kWebuiIcon = 'icons/Icon-maskable-512.png';

/// What a template needs to know about the app.
class AppInfo {
  const AppInfo({
    required this.id,
    required this.name,
    required this.description,
    this.author = '',
  });

  /// From the pubspec `name`: a KernelSU module id and an AERA plugin id.
  factory AppInfo.fromPubspec({required String packageName, String? description}) {
    return AppInfo(
      id: moduleIdFor(packageName),
      name: displayNameFor(packageName),
      description: (description ?? '').replaceAll('\n', ' ').trim(),
    );
  }

  final String id;
  final String name;
  final String description;
  final String author;
}

/// KernelSU, APatch and Magisk accept `^[a-zA-Z][a-zA-Z0-9._-]+$`.
String moduleIdFor(String packageName) {
  var id = packageName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  if (!RegExp(r'^[a-zA-Z]').hasMatch(id)) id = 'app_$id';
  if (id.length < 2) id = '${id}_';
  return id;
}

/// `counter_app` -> `Counter App`.
String displayNameFor(String packageName) => packageName
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Files of `webui/`, relative to it. Everything here lands in the module
/// root; `webroot/` entries overlay the `flutter build web` output.
Map<String, String> webuiTemplate(AppInfo app) => {
  'module.prop': [
    'id=${app.id}',
    'name=${app.name}',
    'version=v$kBuildNameVar',
    'versionCode=$kBuildNumberVar',
    'author=${app.author}',
    'description=${app.description}',
    // WebUI X v608 draws its home-screen shortcut from this PNG (looked up
    // under webroot/ first); `flutter create` puts it in web/icons/.
    'webuiIcon=$kWebuiIcon',
    '',
  ].join('\n'),
  'customize.sh': r'''
# Runs once at install under KernelSU, APatch or Magisk; $MODPATH is the module.
# The app's root process (cli/, if any) ships in bin/.
if [ -d "$MODPATH/bin" ]; then
  set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
fi
''',
  // WebUI X reads webroot/config.json; values from flutter-webui docs/hosts.md.
  // Back is native (history, then close: v608 sends no WX_ON_* events, so
  // "javascript" left Back dead at the root), closing needs no prompt, hidden
  // keeps running (the root shell must survive Home), and ksu.exec needs the
  // SHELL permission on v608 (older versions ignore the key).
  'webroot/config.json':
      '${const JsonEncoder.withIndent('  ').convert({
        'title': app.name,
        'backInterceptor': 'native',
        'exitConfirm': false,
        'killShellWhenBackground': false,
        'pullToRefresh': false,
        'permissions': ['kernelsu.permission.SHELL'],
      })}\n',
};

/// AERA plugin ids: lowercase letters, digits, `-` and `.`.
String aeraIdFor(String moduleId) {
  final id = moduleId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.-]'), '-');
  return id == 'browser' ? 'browser-app' : id;
}

/// Files of `aera/`: the app's part of `plugin.json` (flutter-aera
/// `spec/aerap.md`); the packer adds the fixed and computed fields.
Map<String, String> aeraTemplate(AppInfo app) => {
  'plugin.json':
      '${const JsonEncoder.withIndent('  ').convert({'id': aeraIdFor(app.id), 'name': app.name, 'version': kBuildNameVar, 'description': app.description, 'permissions': <String>[]})}\n',
};

/// Replaces the build variables in a template file.
String expandBuildVars(String content, {required String buildName, required String buildNumber}) =>
    content.replaceAll(kBuildNameVar, buildName).replaceAll(kBuildNumberVar, buildNumber);

/// Magisk's stock installer stub, so the zip also installs where a manager
/// runs it (WebUI X Portable on Magisk). KernelSU and APatch ignore it.
const kUpdateBinary = r'''#!/sbin/sh
umask 022
ui_print() { echo "$1"; }
OUTFD=$2
ZIPFILE=$3
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 20400 ] && { ui_print "! Magisk 20.4+ is needed"; exit 1; }
install_module
exit 0
''';
const kUpdaterScript = '#MAGISK\n';
