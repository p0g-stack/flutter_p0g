import 'dart:io';

import 'package:flutter_p0g/src/adb.dart';
import 'package:flutter_p0g/src/commands/devices.dart';
import 'package:flutter_p0g/src/commands/logs.dart';
import 'package:test/test.dart';

void main() {
  test('parseAdbDevices', () {
    expect(
      parseAdbDevices(
        'List of devices attached\n'
        'emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 '
        'device:emu64xa transport_id:1\n'
        '0123456789ABCDEF       recovery usb:1-1 product:cf model:Cuttlefish transport_id:2\n'
        'R5CT                   unauthorized usb:1-2 transport_id:3\n'
        '\n',
      ),
      [
        (serial: 'emulator-5554', state: 'device', model: 'sdk_gphone64_x86_64'),
        (serial: '0123456789ABCDEF', state: 'recovery', model: 'Cuttlefish'),
        (serial: 'R5CT', state: 'unauthorized', model: null),
      ],
    );
  });

  test('parseProbe on a booted device', () {
    expect(parseProbe('abi:x86_64\n/data/adb/ksud\n', recovery: false), (
      abi: 'x86_64',
      targets: 'webui (ksud)',
    ));
    expect(parseProbe('abi:arm64-v8a\n', recovery: false), (
      abi: 'arm64-v8a',
      targets: 'no root manager',
    ));
  });

  test('parseProbe in recovery', () {
    expect(parseProbe('abi:x86_64\naera\n', recovery: true), (
      abi: 'x86_64',
      targets: 'aera (AERA recovery)',
    ));
    expect(parseProbe('abi:\naera\n', recovery: true), (
      abi: null,
      targets: 'aera (AERA recovery)',
    ));
    expect(parseProbe('abi:x86_64\n', recovery: true).targets, 'recovery (not AERA)');
  });

  test('probe and log scripts are valid sh', () async {
    for (final s in [
      probeScript(recovery: false),
      probeScript(recovery: true),
      webuiLogScript("it's"),
    ]) {
      final r = await Process.run('sh', ['-n', '-c', s]);
      expect(r.exitCode, 0, reason: '$s\n${r.stderr}');
    }
  });

  test('webuiLogScript follows root.log and the newest process logs', () {
    final s = webuiLogScript('counter');
    expect(s, contains("cd '/data/adb/modules/counter/flutter_webui/run'"));
    expect(s, contains('set -- root.log'));
    expect(s, endsWith(r'exec tail -n 50 -F "$@"'));
  });

  test('Adb.rootShell', () {
    final adb = Adb('adb', 'x');
    expect(adb.command(['shell', 'id']), ['adb', '-s', 'x', 'shell', 'id']);
    expect(adb.rootShell('id', recovery: true), ['shell', 'id']);
    expect(adb.rootShell("echo 'a'", recovery: false), ['shell', r"su -c 'echo '\''a'\'''"]);
  });
}
