import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

/// The root managers' own installers, probed in order. Detection runs the
/// probe on the device: a manager's name never selects behaviour.
@visibleForTesting
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

/// POSIX single-quote quoting.
@visibleForTesting
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Pushes a module zip to a device over adb and installs it with the root
/// manager found there. Modules activate on the next boot.
class InstallCommand extends FlutterCommand {
  InstallCommand() {
    argParser
      ..addOption('device-id', abbr: 'd', help: 'adb serial (default: the only device).')
      ..addFlag('reboot', negatable: false, help: 'Reboot after installing.');
  }

  @override
  final name = 'install';

  @override
  final description = 'Install the built WebUI module on a rooted device (adb).';

  @override
  String get invocation => '${runner!.executableName} $name [<module.zip>]';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final zip = _zip();
    final adb = globals.androidSdk?.adbPath ?? 'adb';
    final serial = stringArg('device-id');
    List<String> adbCmd(List<String> args) => [
      adb,
      if (serial != null) ...['-s', serial],
      ...args,
    ];

    final remote = '/data/local/tmp/${zip.basename}';
    await _run(adbCmd(['push', zip.path, remote]));
    await _run(adbCmd(['shell', 'su -c ${shellQuote(installScript(remote))}']));
    await _run(adbCmd(['shell', 'rm -f ${shellQuote(remote)}']));
    if (boolArg('reboot')) {
      await _run(adbCmd(['reboot']));
    } else {
      globals.printStatus('Installed. The module activates on the next boot.');
    }
    return FlutterCommandResult.success();
  }

  File _zip() {
    final rest = argResults!.rest;
    if (rest.isNotEmpty) return globals.fs.file(rest.first);
    final out = project.directory.childDirectory('build').childDirectory('webui');
    final zips = out.existsSync()
        ? out.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()
        : <File>[];
    if (zips.length != 1) {
      throwToolExit('No single module in ${out.path}. Run `flutter_p0g build webui`.');
    }
    return zips.single;
  }

  Future<void> _run(List<String> cmd) async {
    final code = await globals.processUtils.stream(cmd);
    if (code != 0) throwToolExit('${cmd.join(' ')} failed (exit $code).');
  }
}
