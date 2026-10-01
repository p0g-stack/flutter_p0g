import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:yaml/yaml.dart';

import '../templates.dart';

/// Adds the `webui/` and `aera/` platform folders to an existing Flutter
/// app, the way `flutter create --platforms` adds `linux/` or `web/`.
class CreateCommand extends FlutterCommand {
  CreateCommand() {
    argParser
      ..addMultiOption(
        'platforms',
        allowed: ['webui', 'aera'],
        defaultsTo: ['webui', 'aera'],
        help: 'Platform folders to add.',
      )
      ..addOption('author', help: 'module.prop author.', defaultsTo: '')
      ..addFlag('overwrite', negatable: false, help: 'Replace files that already exist.');
  }

  @override
  final name = 'create';

  @override
  final description = 'Add the webui/ and aera/ platform folders to a Flutter app.';

  @override
  String get invocation => '${runner!.executableName} $name [<app directory>]';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final rest = argResults!.rest;
    if (rest.length > 1) throwToolExit('Give at most one app directory.');
    final fs = globals.fs;
    final Directory dir = fs.directory(rest.isEmpty ? '.' : rest.single).absolute;
    final pubspec = dir.childFile('pubspec.yaml');
    if (!pubspec.existsSync()) {
      throwToolExit('${dir.path} has no pubspec.yaml. Create the app first (`flutter create`).');
    }
    final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    final info = AppInfo.fromPubspec(
      packageName: yaml['name'] as String,
      description: yaml['description'] as String?,
    );
    final app = AppInfo(
      id: info.id,
      name: info.name,
      description: info.description,
      author: stringArg('author')!,
    );
    final platforms = stringsArg('platforms');
    final overwrite = boolArg('overwrite');

    // WebUI builds on the web target: make sure it is there.
    if (platforms.contains('webui') && !dir.childDirectory('web').existsSync()) {
      globals.printStatus('Adding web/ (flutter create --platforms=web)...');
      final flutter = fs.path.join(Cache.flutterRoot!, 'bin', 'flutter');
      final code = await globals.processUtils.stream([
        flutter,
        'create',
        '--platforms=web',
        '--no-pub',
        '.',
      ], workingDirectory: dir.path);
      if (code != 0) throwToolExit('flutter create --platforms=web failed.');
    }

    var written = 0;
    void emit(String folder, Map<String, String> files) {
      files.forEach((rel, content) {
        final file = dir.childDirectory(folder).childFile(rel);
        if (file.existsSync() && !overwrite) {
          globals.printTrace('Kept $folder/$rel');
          return;
        }
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
        globals.printStatus('  $folder/$rel');
        written++;
      });
    }

    if (platforms.contains('webui')) emit('webui', webuiTemplate(app));
    if (platforms.contains('aera')) emit('aera', aeraTemplate(app));
    globals.printStatus(written == 0 ? 'Nothing to add.' : 'Wrote $written file(s).');
    return FlutterCommandResult.success();
  }
}
