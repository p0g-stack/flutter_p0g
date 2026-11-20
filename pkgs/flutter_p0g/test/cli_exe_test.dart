import 'package:file/memory.dart';
import 'package:flutter_p0g/src/webui/cli_exe.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;

  setUp(() => fs = MemoryFileSystem.test());

  test('executables: wins', () {
    final dir = fs.directory('/w/cli')..createSync(recursive: true);
    final cli = CliPackage.fromPubspec(dir, 'name: demo_cli\nexecutables:\n  demo: main\n');
    expect(cli.name, 'demo');
    expect(cli.entrypoint.path, '/w/cli/bin/main.dart');
  });

  test('bin/<package>.dart next', () {
    final dir = fs.directory('/w/cli');
    dir.childDirectory('bin').childFile('demo_cli.dart').createSync(recursive: true);
    dir.childDirectory('bin').childFile('other.dart').createSync();
    final cli = CliPackage.fromPubspec(dir, 'name: demo_cli\n');
    expect(cli.name, 'demo_cli');
    expect(cli.entrypoint.path, '/w/cli/bin/demo_cli.dart');
  });

  test('the only bin/ script last', () {
    final dir = fs.directory('/w/cli');
    dir.childDirectory('bin').childFile('serve.dart').createSync(recursive: true);
    final cli = CliPackage.fromPubspec(dir, 'name: demo_cli\n');
    expect(cli.name, 'serve');
  });

  test('find looks in the app, then the workspace root', () {
    fs.directory('/w/app').createSync(recursive: true);
    expect(CliPackage.find(fs.directory('/w/app')), isNull);
    fs.directory('/w/cli/bin').createSync(recursive: true);
    fs.file('/w/cli/pubspec.yaml').writeAsStringSync('name: w_cli\nexecutables:\n  w: w\n');
    expect(CliPackage.find(fs.directory('/w/app'))!.dir.path, '/w/cli');
  });
}
