import 'package:file/memory.dart';
import 'package:flutter_p0g_tool/src/p0g_repository.dart';
import 'package:flutter_p0g_tool/src/webui/webui_packages.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the repository is the monorepo around this package, with the WebUI sources', () async {
    final repo = await p0gRepository();
    expect(repo.childDirectory('pkgs').childDirectory('flutter_p0g').existsSync(), isTrue);
    final packages = webuiSourcePackages(repo);
    expect(packages, {
      'flutter_webui': 'pkgs/flutter_webui',
      'flutter_webui_client': 'pkgs/flutter_webui_client',
      'flutter_webui_root': 'pkgs/flutter_webui_root',
      'flutter_webui_web_sdk': 'web_sdk',
      'clipboard_webui': 'pkgs/webui/clipboard_webui',
      'dynamic_color_webui': 'pkgs/webui/dynamic_color_webui',
      'file_selector_webui': 'pkgs/webui/file_selector_webui',
      'flutter_local_notifications_webui': 'pkgs/webui/flutter_local_notifications_webui',
      'path_provider_webui': 'pkgs/webui/path_provider_webui',
      'permission_handler_webui': 'pkgs/webui/permission_handler_webui',
      'share_plus_webui': 'pkgs/webui/share_plus_webui',
      'shared_preferences_webui': 'pkgs/webui/shared_preferences_webui',
      'url_launcher_webui': 'pkgs/webui/url_launcher_webui',
      'webui_app_plane': 'pkgs/webui/webui_app_plane',
    });
    expect(
      webuiImplementations(webuiPackagesDir(repo)),
      containsPair('share_plus', 'share_plus_webui'),
    );
  });

  test('a pub git cache checkout resolves by path from outside it', () async {
    // `dart pub global activate --source git <url> --git-path pkgs/flutter_p0g`
    // checks the whole repository out at <PUB_CACHE>/git/<repo>-<commit>/.
    final fs = MemoryFileSystem.test();
    await context.run<void>(
      overrides: {FileSystem: () => fs},
      body: () {
        final repo = fs.directory('/pub-cache/git/p0g-0123abc');
        repo.childFile('pubspec.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync('name: p0g_workspace\nenvironment:\n  sdk: ^3.13.0\n');
        for (final (path, name) in [
          ('pkgs/flutter_webui', 'flutter_webui'),
          ('pkgs/flutter_webui_client', 'flutter_webui_client'),
          ('pkgs/flutter_webui_root', 'flutter_webui_root'),
          ('web_sdk', 'flutter_webui_web_sdk'),
          ('pkgs/webui/url_launcher_webui', 'url_launcher_webui'),
        ]) {
          repo.childFile('$path/pubspec.yaml')
            ..createSync(recursive: true)
            ..writeAsStringSync('name: $name\n');
        }
        repo.childDirectory('pkgs/webui/docs').createSync(recursive: true);

        final packages = webuiSourcePackages(repo);
        expect(packages.keys, contains('url_launcher_webui'));
        expect(packages.keys, isNot(contains('docs')));
        final pubspec = loadYaml(webuiSourcesPubspec(repo, packages)) as YamlMap;
        expect(pubspec['environment']['sdk'], '^3.13.0');
        final deps = pubspec['dependencies'] as YamlMap;
        expect(deps['flutter_webui']['path'], '/pub-cache/git/p0g-0123abc/pkgs/flutter_webui');
        expect(deps['flutter_webui_web_sdk']['path'], '/pub-cache/git/p0g-0123abc/web_sdk');
        expect(
          deps['url_launcher_webui']['path'],
          '/pub-cache/git/p0g-0123abc/pkgs/webui/url_launcher_webui',
        );
      },
    );
  });
}
