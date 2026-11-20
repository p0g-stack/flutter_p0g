import 'package:file/memory.dart';
import 'package:flutter_p0g_tool/src/squadron.dart';
import 'package:test/test.dart';

void main() {
  test('finds the workspace member that depends on squadron_process', () {
    final fs = MemoryFileSystem.test();
    final root = fs.directory('/ws')..createSync();
    root.childFile('pubspec.yaml').writeAsStringSync('name: ws\nworkspace:\n  - core\n  - cli\n');
    root.childDirectory('core').childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: core\ndependencies:\n  meta: any\n');
    root.childDirectory('cli').childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: cli\ndependencies:\n  squadron_process:\n    git: x\n');
    expect(squadronProcessUser(root)?.path, '/ws/cli');

    root.childDirectory('cli').childFile('pubspec.yaml').writeAsStringSync('name: cli\n');
    expect(squadronProcessUser(root), isNull);
  });
}
