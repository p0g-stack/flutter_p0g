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
    final r = overlayPackageConfig(
      app,
      [(config: src, graph: graph, dir: srcDir)],
      ['flutter_webui'],
    );
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
    final r = overlayPackageConfig(
      app,
      [(config: src, graph: graph, dir: srcDir)],
      ['flutter_webui'],
    );
    expect(r.added, ['flutter_webui']);
    final client = (r.config['packages']! as List).cast<Map>().firstWhere(
      (p) => p['name'] == 'flutter_webui_client',
    );
    expect(client['rootUri'], 'file:///git/client');
  });

  test('a second source fills what the first lacks; the first wins', () {
    final pkgs = {
      'configVersion': 2,
      'packages': [
        {'name': 'url_launcher_webui', 'rootUri': '../packages/url_launcher_webui'},
        {'name': 'webui_app_plane', 'rootUri': '../packages/webui_app_plane'},
        {'name': 'flutter_webui_client', 'rootUri': 'file:///other/client'},
      ],
    };
    final pkgsGraph = {
      'packages': [
        {
          'name': 'url_launcher_webui',
          'dependencies': ['webui_app_plane', 'flutter_webui_client'],
        },
        {
          'name': 'webui_app_plane',
          'dependencies': ['flutter_webui_client'],
        },
      ],
    };
    final app = {
      'packages': [
        {'name': 'flutter', 'rootUri': 'file:///sdk/packages/flutter'},
      ],
    };
    final r = overlayPackageConfig(
      app,
      [
        (config: src, graph: graph, dir: srcDir),
        (
          config: pkgs,
          graph: pkgsGraph,
          dir: Uri.parse('file:///cache/webui-packages/src/.dart_tool/'),
        ),
      ],
      ['flutter_webui', 'url_launcher_webui'],
    );
    expect(r.added, containsAll(['url_launcher_webui', 'webui_app_plane', 'flutter_webui']));
    final byName = {for (final p in r.config['packages']! as List) (p as Map)['name']: p};
    expect(
      byName['flutter_webui_client']!['rootUri'],
      'file:///cache/flutter-webui/src/packages/flutter_webui_client',
    );
    expect(
      byName['url_launcher_webui']!['rootUri'],
      'file:///cache/webui-packages/src/packages/url_launcher_webui',
    );
  });

  test('the graph makes the *_webui packages direct dependencies of the app', () {
    final appGraph = {
      'roots': ['counter'],
      'packages': [
        {
          'name': 'counter',
          'dependencies': ['url_launcher'],
          'devDependencies': <String>[],
        },
        {
          'name': 'url_launcher',
          'dependencies': ['url_launcher_web'],
        },
        {'name': 'url_launcher_web', 'dependencies': <String>[]},
      ],
    };
    expect(closureOf(appGraph, 'counter'), {'url_launcher', 'url_launcher_web'});
    final direct = webuiPackagesFor(
      closureOf(appGraph, 'counter'),
      {'url_launcher'},
      {'url_launcher': 'url_launcher_webui', 'share_plus': 'share_plus_webui'},
    );
    expect(direct, ['url_launcher_webui']);
    final g = overlayPackageGraph(
      appGraph,
      root: 'counter',
      added: ['url_launcher_webui', 'webui_app_plane'],
      direct: direct,
      dependencies: {
        'url_launcher_webui': ['webui_app_plane'],
      },
    );
    final byName = {for (final p in g['packages']! as List) (p as Map)['name']: p};
    expect(byName['counter']!['dependencies'], ['url_launcher', 'url_launcher_webui']);
    expect(byName['counter']!['devDependencies'], isEmpty);
    expect(byName['url_launcher_webui']!['dependencies'], ['webui_app_plane']);
    expect(byName['webui_app_plane']!['dependencies'], isEmpty);
    expect(g['roots'], ['counter']);
  });

  test('an app that already names a *_webui package keeps it', () {
    expect(
      webuiPackagesFor({'url_launcher'}, {'url_launcher_webui'}, {
        'url_launcher': 'url_launcher_webui',
      }),
      isEmpty,
    );
  });

  test('a plugin only an added package brings in gets its *_webui too', () {
    expect(
      webuiPackagesFor(
        {'share_plus', 'flutter'},
        const {},
        {'share_plus': 'share_plus_webui', 'url_launcher': 'url_launcher_webui'},
        addedDependencies: {
          // As webui-packages resolves them: no edge to url_launcher itself.
          'share_plus_webui': ['share_plus', 'url_launcher_web', 'url_launcher_webui'],
          'url_launcher_webui': ['url_launcher_platform_interface', 'url_launcher_web'],
        },
      ),
      ['share_plus_webui', 'url_launcher_webui'],
    );
  });

  test('always-added packages come in and bring what they reach', () {
    expect(
      webuiPackagesFor(
        {'flutter'},
        const {},
        {'url_launcher': 'url_launcher_webui'},
        addedDependencies: {
          'clipboard_webui': ['flutter_webui', 'webui_app_plane'],
        },
        always: {'clipboard_webui'},
      ),
      ['clipboard_webui'],
    );
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
