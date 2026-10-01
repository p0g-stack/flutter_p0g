import 'dart:io';

import 'package:flutter_p0g/src/commands/run_aera.dart';
import 'package:test/test.dart';

void main() {
  test('data dir follows /sdcard/AERA, as AERA does', () {
    final s = aeraDataDirScript('counter');
    expect(s, contains('[ -d /sdcard/AERA ]'));
    expect(s, contains('/sdcard/AERA/plugin-data/counter'));
    expect(s, contains('/tmp/aera/plugin-data/counter'));
  });

  test('debug setup writes the switch and clears the old URL', () async {
    final tmp = Directory.systemTemp.createTempSync('aera_debug');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final d = '${tmp.path}/plugin-data/counter';
    Directory(d).createSync(recursive: true);
    File('$d/vm-service-url').writeAsStringSync('http://127.0.0.1:1/stale=/');
    final r = await Process.run('sh', ['-c', aeraDebugSetupScript(d, 8181)]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(File('$d/engine-switches').readAsStringSync(), '--vm-service-port=8181\n');
    expect(File('$d/vm-service-url').existsSync(), isFalse);
  });
}
