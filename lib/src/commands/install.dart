import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

import '../adb.dart';
import '../aera/install.dart';

export '../adb.dart' show shellQuote;

/// The root managers' own installers, probed in order. Detection runs the
/// probe on the device: a manager's name never selects behaviour.
const kManagerInstallers = <({String probe, String install})>[
  (probe: '/data/adb/ksud', install: '/data/adb/ksud module install'),
  (probe: '/data/adb/apd', install: '/data/adb/apd module install'),
  (probe: '/data/adb/magisk', install: 'magisk --install-module'),
];

/// One shell line that installs [remoteZip] with the first installer present.
@visibleForTesting
String installScript(String remoteZip) {
  final q = shellQuote(remoteZip);
  final branches = [
    for (final (i, m) in kManagerInstallers.indexed)
      '${i == 0 ? 'if' : 'elif'} [ -e ${m.probe} ]; then ${m.install} $q',
  ];
  return '${branches.join('; ')}; else echo "no ksud, apd or magisk found" >&2; exit 3; fi';
}

/// Which target a package is for, by its extension.
@visibleForTesting
String? targetOf(String path) => path.endsWith('.aerap')
    ? 'aera'
    : path.endsWith('.zip')
    ? 'webui'
    : null;

/// Installs a built package over adb: a WebUI module zip with the root
/// manager on a booted device, or an `.aerap` into AERA recovery's plugin
/// store.
class InstallCommand extends FlutterCommand {
  InstallCommand() {
    argParser
      ..addOption('device-id', abbr: 'd', help: 'adb serial (default: the only device).')
      ..addOption(
        'target',
        allowed: ['webui', 'aera'],
        help: 'What to install when build/ holds both (default: from the package).',
      )
      ..addFlag(
        'ram',
        negatable: false,
        help: "aera: install into AERA's RAM store (gone on reboot) instead of internal storage.",
      )
      ..addFlag('open', negatable: false, help: 'aera: open the plugin once installed.')
      ..addFlag('reboot', negatable: false, help: 'webui: reboot after installing.');
  }

  @override
  final name = 'install';

  @override
  final description =
      'Install the built WebUI module on a rooted device, or the AERA plugin in AERA recovery (adb).';

  @override
  String get invocation => '${runner!.executableName} $name [<module.zip | plugin.aerap>]';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final package = _package();
    final adb = Adb.find(stringArg('device-id'));
    if (targetOf(package.path) == 'aera') {
      await _installAera(adb, package);
    } else {
      await _installWebui(adb, package);
    }
    return FlutterCommandResult.success();
  }

  Future<void> _installWebui(Adb adb, File zip) async {
    final remote = '/data/local/tmp/${zip.basename}';
    await adb.stream(['push', zip.path, remote]);
    await adb.stream(adb.rootShell(installScript(remote), recovery: false));
    await adb.stream(['shell', 'rm -f ${shellQuote(remote)}']);
    if (boolArg('reboot')) {
      await adb.stream(['reboot']);
    } else {
      globals.printStatus('Installed. The module activates on the next boot.');
    }
  }

  Future<void> _installAera(Adb adb, File aerap) async {
    final AerapPackage package;
    try {
      package = AerapPackage.decode(aerap.readAsBytesSync());
    } on FormatException catch (e) {
      throwToolExit('${aerap.path}: ${e.message}');
    }
    final state = await adb.state();
    if (state != 'recovery') {
      throwToolExit(
        state == null
            ? 'No adb device.'
            : 'The device is in "$state" state; AERA plugins install in recovery. '
                  'Run `adb reboot recovery` first.',
      );
    }
    if ((await adb.run(['shell', '[ -p $kAeraRpcIn ] && echo yes'], check: false))?.trim() !=
        'yes') {
      globals.printWarning('This recovery has no AERA RPC channel; is it AERA?');
    }

    final pushed = '/tmp/flutter_p0g-${package.id}';
    final tmp = globals.fs.systemTempDirectory.createTempSync('p0g_aerap');
    try {
      tmp.childFile('plugin.json').writeAsBytesSync(package.manifest);
      tmp.childFile('runtime.xz').writeAsBytesSync(package.runtimeXz);
      if (package.signature != null) {
        tmp.childFile('plugin.json.sig').writeAsBytesSync(package.signature!);
      }
      await adb.run(['shell', 'rm -rf ${shellQuote(pushed)} && mkdir -p ${shellQuote(pushed)}']);
      for (final f in tmp.listSync().whereType<File>()) {
        await adb.run(['push', f.path, '$pushed/${f.basename}']);
      }
    } finally {
      tmp.deleteSync(recursive: true);
    }
    final ram = boolArg('ram');
    await adb.stream(
      adb.rootShell(
        aeraInstallScript(
          pushed: pushed,
          root: ram ? kAeraMemoryRoot : kAeraStorageRoot,
          id: package.id,
          sha256: package.payloadSha256,
          signed: package.signature != null,
        ),
        recovery: true,
      ),
    );
    globals.printStatus(
      'Installed ${package.id} in AERA ${ram ? 'RAM (until reboot)' : 'internal storage'}.',
    );
    if (boolArg('open')) await openAeraPlugin(adb, package.id);
  }

  File _package() {
    final rest = argResults!.rest;
    if (rest.isNotEmpty) {
      final file = globals.fs.file(rest.first);
      if (!file.existsSync()) throwToolExit('No such package: ${file.path}');
      if (targetOf(file.path) == null) throwToolExit('Not a module zip or .aerap: ${file.path}');
      return file;
    }
    final build = project.directory.childDirectory('build');
    List<File> built(String target, String ext) {
      final dir = build.childDirectory(target);
      return dir.existsSync()
          ? dir.listSync().whereType<File>().where((f) => f.path.endsWith(ext)).toList()
          : <File>[];
    }

    final target = stringArg('target');
    final candidates = {
      if (target != 'aera') 'webui': built('webui', '.zip'),
      if (target != 'webui') 'aera': built('aera', '.aerap'),
    }..removeWhere((_, files) => files.isEmpty);
    if (candidates.length > 1) {
      throwToolExit('build/ holds a WebUI module and an AERA plugin: pass --target.');
    }
    if (candidates.isEmpty || candidates.values.single.length != 1) {
      throwToolExit(
        'No single package in ${build.path}. Run `flutter_p0g build webui` or `build aera`, '
        'or name the package.',
      );
    }
    return candidates.values.single.single;
  }
}

/// Opens installed plugin [id] in AERA over its RPC channel (needs the
/// Host API 3 patch series' `plugin` operation).
Future<void> openAeraPlugin(Adb adb, String id) async {
  final out = await adb.run([
    'shell',
    aeraRpcScript(aeraRpcRequest('plugin', {'action': 'open', 'id': id})),
  ]);
  final events = parseAeraRpcEvents(out ?? '');
  events.logs.forEach(globals.printStatus);
  if (events.code != 0) {
    throwToolExit(
      'AERA could not open $id: '
      '${events.errors.isEmpty ? 'no result (code ${events.code})' : events.errors.join('; ')}',
    );
  }
}
