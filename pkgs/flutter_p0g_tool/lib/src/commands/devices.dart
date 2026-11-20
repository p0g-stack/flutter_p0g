import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

import '../adb.dart';
import '../aera/install.dart' show kAeraRpcIn;
import 'install.dart' show kManagerInstallers;

/// Prints `abi:<abi>`, then one line per root manager installer found (WebUI),
/// or `aera` when AERA's RPC channel is there (recovery). The probes are
/// the ones `install` uses.
@visibleForTesting
String probeScript({required bool recovery}) {
  const abi = r'echo abi:$(getprop ro.product.cpu.abi); ';
  if (recovery) return '$abi[ -p $kAeraRpcIn ] && echo aera; true';
  final probes = [for (final m in kManagerInstallers) '[ -e ${m.probe} ] && echo ${m.probe}'];
  return '$abi'
      'su -c ${shellQuote('${probes.join('; ')}; true')} 2>/dev/null; true';
}

/// What a device can run, from [probeScript]'s output.
@visibleForTesting
({String? abi, String targets}) parseProbe(String out, {required bool recovery}) {
  final lines = [
    for (final l in out.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  final abi = [
    for (final l in lines)
      if (l.startsWith('abi:') && l.length > 4) l.substring(4),
  ].firstOrNull;
  final found = lines.toSet();
  if (recovery) {
    return (
      abi: abi,
      targets: found.contains('aera') ? 'aera (AERA recovery)' : 'recovery (not AERA)',
    );
  }
  final managers = [
    for (final m in kManagerInstallers)
      if (found.contains(m.probe)) m.probe.split('/').last,
  ];
  return (
    abi: abi,
    targets: managers.isEmpty ? 'no root manager' : 'webui (${managers.join(', ')})',
  );
}

/// Lists adb devices and what each can run: WebUI modules on a booted,
/// rooted device, AERA plugins in AERA recovery.
class DevicesCommand extends FlutterCommand {
  DevicesCommand();

  @override
  final name = 'devices';

  @override
  final description = 'List adb devices and whether they take WebUI modules or AERA plugins.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final adb = Adb.find(null);
    final devices = parseAdbDevices(await adb.run(['devices', '-l']) ?? '');
    if (devices.isEmpty) {
      globals.printStatus('No adb devices.');
      return FlutterCommandResult.success();
    }
    for (final d in devices) {
      final recovery = d.state == 'recovery';
      String detail = d.state;
      if (d.state == 'device' || recovery) {
        final out = await Adb(
          adb.path,
          d.serial,
        ).run(['shell', probeScript(recovery: recovery)], check: false);
        final probe = parseProbe(out ?? '', recovery: recovery);
        detail = '${probe.abi ?? '?'} • ${probe.targets}';
      }
      globals.printStatus('${d.model ?? d.serial} (${d.serial}) • $detail');
    }
    return FlutterCommandResult.success();
  }
}
