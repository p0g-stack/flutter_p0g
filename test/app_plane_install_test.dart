import 'dart:io';

import 'package:flutter_p0g/src/webui/module.dart';
import 'package:test/test.dart';

void main() {
  test('installer pauses verification only during a session and restores it', () {
    final dir = Directory.systemTemp.createTempSync('app-plane-install-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bin = Directory('${dir.path}/bin')..createSync();
    final apkDir = Directory('${dir.path}/payload')..createSync();
    File('${apkDir.path}/app.apk').writeAsStringSync('apk');
    final script = appPlaneInstallScript((package: 'com.example.demo', versionCode: 1011))
        .replaceFirst(r'T=/data/local/tmp/webui-app-plane-$PKG.apk', 'T=${dir.path}/stage.apk');
    final installer = File('${apkDir.path}/app-install.sh')..writeAsStringSync(script);
    final settings = File('${bin.path}/settings')
      ..writeAsStringSync('''#!/bin/sh
file="\$STATE/\$3"
case "\$1" in
  get) if [ -f "\$file" ]; then cat "\$file"; else echo null; fi ;;
  put)
    if [ "\$FAIL_PAUSE" = 1 ] && [ "\$3" = package_verifier_enable ] && [ "\$4" = 0 ]; then exit 1; fi
    printf '%s\\n' "\$4" > "\$file" ;;
  delete) rm -f "\$file" ;;
esac
''');
    final pm = File('${bin.path}/pm')
      ..writeAsStringSync('''#!/bin/sh
case "\$1" in
  path) [ "\$SKIP" = 1 ] && echo package:/installed.apk ;;
  install-create)
    [ "\$(cat "\$STATE/verifier_verify_adb_installs")" = 0 ] || exit 2
    [ "\$(cat "\$STATE/package_verifier_enable")" = 0 ] || exit 2
    echo 'Success: created install session [7]' ;;
  install-write) echo 'Success' ;;
  install-commit)
    [ "\$(cat "\$STATE/verifier_verify_adb_installs")" = 0 ] || exit 2
    [ "\$(cat "\$STATE/package_verifier_enable")" = 0 ] || exit 2
    if [ "\$FAIL_COMMIT" = 1 ]; then echo 'Failure [INSTALL_FAILED]'; else echo Success; fi ;;
esac
''');
    for (final file in [settings, pm]) {
      expect(Process.runSync('chmod', ['755', file.path]).exitCode, 0);
    }
    for (final command in ['chown', 'chcon', 'appops', 'dumpsys']) {
      final file = File('${bin.path}/$command')
        ..writeAsStringSync(
          command == 'dumpsys'
              ? '#!/bin/sh\n[ "\$SKIP" = 1 ] && echo versionCode=1011\n'
              : '#!/bin/sh\nexit 0\n',
        );
      expect(Process.runSync('chmod', ['755', file.path]).exitCode, 0);
    }
    final state = Directory('${dir.path}/state')..createSync();
    final adb = File('${state.path}/verifier_verify_adb_installs');
    final package = File('${state.path}/package_verifier_enable');
    final environment = {
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'STATE': state.path,
    };

    ProcessResult run([Map<String, String> extra = const {}]) =>
        Process.runSync('sh', [installer.path], environment: {...environment, ...extra});

    adb.writeAsStringSync('1\n');
    package.writeAsStringSync('2\n');
    expect(run().exitCode, 0);
    expect(adb.readAsStringSync(), '1\n');
    expect(package.readAsStringSync(), '2\n');

    expect(run({'FAIL_COMMIT': '1'}).exitCode, 1);
    expect(adb.readAsStringSync(), '1\n');
    expect(package.readAsStringSync(), '2\n');
    expect(run({'FAIL_PAUSE': '1'}).exitCode, 1);
    expect(adb.readAsStringSync(), '1\n');
    expect(package.readAsStringSync(), '2\n');

    package.deleteSync();
    expect(run().exitCode, 0);
    expect(package.existsSync(), isFalse);
    expect(adb.readAsStringSync(), '1\n');

    expect(run({'SKIP': '1'}).exitCode, 0);
    expect(package.existsSync(), isFalse);
    expect(adb.readAsStringSync(), '1\n');
  });
}
