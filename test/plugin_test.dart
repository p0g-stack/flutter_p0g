import 'package:flutter_p0g/src/webui/plugin.dart';
import 'package:test/test.dart';

void main() {
  final src = {
    'configVersion': 2,
    'packages': [
      for (final n in [
        'flutter_webui',
        'flutter_webui_client',
        'flutter_webui_root',
        'args',
        'web',
      ])
        {'name': n, 'rootUri': '../packages/$n', 'packageUri': 'lib/', 'languageVersion': '3.13'},
      {'name': 'flutter', 'rootUri': 'file:///sdk/packages/flutter', 'packageUri': 'lib/'},
      {'name': 'test', 'rootUri': '../test', 'packageUri': 'lib/'},
    ],
  };
  final graph = {
    'packages': [
      {
        'name': 'flutter_webui',
        'dependencies': ['flutter', 'flutter_webui_client', 'web'],
        'devDependencies': ['test'],
      },
      {
        'name': 'flutter_webui_client',
        'dependencies': ['flutter_webui_root', 'web'],
      },
      {
        'name': 'flutter_webui_root',
        'dependencies': ['args'],
      },
      {'name': 'flutter', 'dependencies': <String>[]},
    ],
  };
  final srcDir = Uri.parse('file:///cache/flutter-webui/src/.dart_tool/');

  test('adds the plugin closure the app lacks, absolute, without dev deps', () {
    final app = {
      'configVersion': 2,
      'packages': [
        {'name': 'flutter', 'rootUri': 'file:///sdk/packages/flutter', 'packageUri': 'lib/'},
        {'name': 'counter', 'rootUri': '../', 'packageUri': 'lib/'},
      ],
    };
    final r = overlayPackageConfig(app, src, graph, srcConfigDir: srcDir);
    expect(r.added, ['args', 'flutter_webui', 'flutter_webui_client', 'flutter_webui_root', 'web']);
    final pkgs = {for (final p in r.config['packages']! as List) (p as Map)['name']: p};
    expect(
      pkgs['flutter_webui']!['rootUri'],
      'file:///cache/flutter-webui/src/packages/flutter_webui',
    );
    expect(pkgs['counter']!['rootUri'], '../');
    expect(pkgs.containsKey('test'), isFalse);
    expect(r.config['configVersion'], 2);
  });

  test("keeps the app's own client", () {
    final app = {
      'packages': [
        {'name': 'flutter', 'rootUri': 'file:///sdk/packages/flutter'},
        {'name': 'flutter_webui_client', 'rootUri': 'file:///git/client'},
        {'name': 'flutter_webui_root', 'rootUri': 'file:///git/root'},
        {'name': 'args', 'rootUri': 'file:///pub/args'},
        {'name': 'web', 'rootUri': 'file:///pub/web'},
      ],
    };
    final r = overlayPackageConfig(app, src, graph, srcConfigDir: srcDir);
    expect(r.added, ['flutter_webui']);
    final client = (r.config['packages']! as List).cast<Map>().firstWhere(
      (p) => p['name'] == 'flutter_webui_client',
    );
    expect(client['rootUri'], 'file:///git/client');
  });

  test('entrypoint registers the plugin then runs the app', () {
    final code = webuiEntrypoint('package:counter/main.dart');
    expect(code, contains("import 'package:counter/main.dart' as app;"));
    expect(code, contains("import 'package:flutter_webui/flutter_webui_web.dart';"));
    expect(
      code.indexOf('FlutterWebUi.registerWith(webPluginRegistrar)'),
      lessThan(code.indexOf('app.main')),
    );
  });
}
