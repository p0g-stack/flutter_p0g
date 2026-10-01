import 'package:file/memory.dart';
import 'package:flutter_p0g/src/squadron.dart';
import 'package:test/test.dart';

void main() {
  test('detects an existing squadron override', () {
    expect(overridesSquadron(null), isFalse);
    expect(overridesSquadron('dependency_overrides:\n  other:\n    path: x\n'), isFalse);
    expect(
      overridesSquadron('dependency_overrides:\n  squadron:\n    path: .dart_tool/s\n'),
      isTrue,
    );
  });

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
