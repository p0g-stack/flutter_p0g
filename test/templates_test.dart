import 'dart:convert';

import 'package:flutter_p0g/src/templates.dart';
import 'package:test/test.dart';

void main() {
  test('module id keeps valid pubspec names and fixes the rest', () {
    expect(moduleIdFor('counter_app'), 'counter_app');
    expect(moduleIdFor('_private'), 'app__private');
    expect(moduleIdFor('9lives'), 'app_9lives');
    expect(moduleIdFor('a'), 'a_');
    expect(moduleIdFor('café'), 'caf_');
  });

  test('display name from package name', () {
    expect(displayNameFor('counter_app'), 'Counter App');
    expect(displayNameFor('demo'), 'Demo');
  });

  test('webui template: module.prop carries build vars, config keeps the shell', () {
    final files = webuiTemplate(
      const AppInfo(id: 'counter', name: 'Counter', description: 'd', author: 'Yuv'),
    );
    expect(files.keys, containsAll(['module.prop', 'customize.sh', 'webroot/config.json']));
    final prop = files['module.prop']!;
    expect(prop, contains('id=counter\n'));
    expect(prop, contains('version=v$kBuildNameVar\n'));
    expect(prop, contains('versionCode=$kBuildNumberVar\n'));
    expect(prop, contains('author=Yuv\n'));
    final config = jsonDecode(files['webroot/config.json']!) as Map;
    expect(config['killShellWhenBackground'], false);
    expect(config['title'], 'Counter');
  });

  test('pubspec description is flattened to one line', () {
    final app = AppInfo.fromPubspec(packageName: 'x_y', description: 'two\nlines ');
    expect(app.description, 'two lines');
    expect(app.name, 'X Y');
  });

  test('expandBuildVars', () {
    expect(
      expandBuildVars('v$kBuildNameVar ($kBuildNumberVar)', buildName: '1.2.3', buildNumber: '7'),
      'v1.2.3 (7)',
    );
  });

  test('aera template carries only the app fields, with an AERA id', () {
    final files = aeraTemplate(const AppInfo(id: 'my_app', name: 'C', description: ''));
    final json = jsonDecode(files['plugin.json']!) as Map;
    expect(json['id'], 'my-app');
    expect(json['version'], kBuildNameVar);
    expect(json['permissions'], isEmpty);
    expect(json.containsKey('schema'), isFalse);
  });
}
