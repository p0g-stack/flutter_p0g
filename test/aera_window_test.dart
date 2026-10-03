import 'dart:io';

import 'package:flutter_p0g/src/aera/window.dart';
import 'package:test/test.dart';

void main() {
  test('the entrypoint installs the binding before the app runs', () {
    final code = aeraEntrypoint('package:counter/main.dart');
    expect(code, contains("import 'package:counter/main.dart' as app;"));
    expect(code, contains("import 'package:aera_window/aera_window.dart' as aera;"));
    expect(code.indexOf('aera.AeraWindowBinding.install()'), lessThan(code.indexOf('app.main')));
  });

  // Runs the generated entrypoint against a stand-in aera_window and app
  // mains with and without args.
  for (final (name, appMain, expected) in [
    ('no args', "void main() => print('app');", 'install\napp\n'),
    ('args', "void main(List<String> a) => print('app \${a.length}');", 'install\napp 0\n'),
    ('async', "Future<void> main() async { await null; print('app'); }", 'install\napp\n'),
  ]) {
    test('the entrypoint runs a main with $name', () async {
      final tmp = Directory.systemTemp.createTempSync('aera_entry');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/aw/lib/aera_window.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "class AeraWindowBinding { static void install() => print('install'); }\n",
        );
      File('${tmp.path}/app/lib/main.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('$appMain\n');
      File('${tmp.path}/app/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
{"configVersion": 2, "packages": [
  {"name": "aera_window", "rootUri": "../../aw/", "packageUri": "lib/", "languageVersion": "3.8"},
  {"name": "counter", "rootUri": "../", "packageUri": "lib/", "languageVersion": "3.8"}
]}''');
      final entry = File('${tmp.path}/app/.dart_tool/flutter_p0g/aera_main.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(aeraEntrypoint('package:counter/main.dart'));
      final r = await Process.run(Platform.resolvedExecutable, [
        '--packages=${tmp.path}/app/.dart_tool/package_config.json',
        entry.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, expected);
    });
  }
}
