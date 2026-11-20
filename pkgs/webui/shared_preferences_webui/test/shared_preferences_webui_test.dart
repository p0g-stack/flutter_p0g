// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences_webui/src/shared_preferences_webui_impl.dart';
import 'package:webui_app_plane/testing.dart';

/// A root channel whose `ksud module config` keeps values in [config].
FakeRootChannel ksud(Map<String, String> config) => FakeRootChannel(
  handler: (run) {
    final a = run.shArgs; // [module id, ksud, module, config, cmd, key, ...]
    if (a.length < 6 || a[1] != ModuleConfigPrefs.ksud) {
      return const FakeProcessResult(exitCode: 127);
    }
    final key = '${a[0]}/${a[5]}';
    switch (a[4]) {
      case 'get':
        final v = config[key];
        return v == null
            ? FakeProcessResult(exitCode: 1, stderr: "Key '${a[5]}' not found")
            : FakeProcessResult(stdout: '$v\n');
      case 'set':
        config[key] = run.stdinText;
        return const FakeProcessResult();
    }
    return const FakeProcessResult(exitCode: 2);
  },
);

const key = 'demo/${ModuleConfigPrefs.configKey}';
const options = SharedPreferencesOptions();

void main() {
  test('stores every value type in one module config value', () async {
    final config = <String, String>{};
    final fake = ksud(config);
    final store = SharedPreferencesWebUiStore(
      stock: InMemorySharedPreferencesStore.empty(),
      prefs: ModuleConfigPrefs(fake.root()),
    );
    expect(await store.getAll(), isEmpty);
    await store.setValue('Bool', 'flutter.b', true);
    await store.setValue('Int', 'flutter.i', 3);
    await store.setValue('Double', 'flutter.d', 1.0);
    await store.setValue('String', 'flutter.s', 'x');
    await store.setValue('StringList', 'flutter.l', ['a', 'b']);
    await store.setValue('String', 'other', 'kept');
    expect(await store.getAll(), {
      'flutter.b': true,
      'flutter.i': 3,
      'flutter.d': 1.0,
      'flutter.s': 'x',
      'flutter.l': ['a', 'b'],
    });
    expect((await store.getAll())['flutter.d'], isA<double>());
    expect((await store.getAll())['flutter.l'], isA<List<String>>());
    // The module id goes in KSU_MODULE; ksud runs as root.
    final set = fake.runs.lastWhere((r) => r.shArgs[4] == 'set');
    expect(set.argv[2], contains('KSU_MODULE=\$1'));
    expect(set.shArgs, [
      'demo',
      '/data/adb/ksu/bin/ksud',
      'module',
      'config',
      'set',
      'webui.shared_preferences',
      '--stdin',
    ]);
    expect(config.keys, [key]);

    await store.clear();
    expect(await store.getAll(), isEmpty);
    expect(await store.getAllWithPrefix(''), {'other': 'kept'});
    await store.remove('other');
    expect(config[key], '{}');
  });

  test('the async API shares the same value', () async {
    final config = <String, String>{};
    final prefs = ModuleConfigPrefs(ksud(config).root());
    final async = SharedPreferencesWebUiAsync(
      stock: InMemorySharedPreferencesAsync.empty(),
      prefs: prefs,
    );
    await async.setInt('n', 7, options);
    await async.setStringList('l', ['x'], options);
    expect(await async.getInt('n', options), 7);
    expect(await async.getString('n', options), isNull);
    expect(await async.getStringList('l', options), ['x']);
    expect(
      await async.getKeys(
        const GetPreferencesParameters(filter: PreferencesFilters()),
        options,
      ),
      {'n', 'l'},
    );
    await async.clear(
      const ClearPreferencesParameters(
        filter: PreferencesFilters(allowList: {'n'}),
      ),
      options,
    );
    expect(config[key], '{"l":["x"]}');
  });

  test('changes run one at a time, each on a fresh read', () async {
    final config = <String, String>{};
    final store = SharedPreferencesWebUiStore(
      stock: InMemorySharedPreferencesStore.empty(),
      prefs: ModuleConfigPrefs(ksud(config).root()),
    );
    await Future.wait([
      for (var i = 0; i < 5; i++) store.setValue('Int', 'flutter.k$i', i),
    ]);
    expect((await store.getAll()).length, 5);
    // Something else (another page) changed it: the next read sees that.
    config[key] = '{"flutter.z":true}';
    expect(await store.getAll(), {'flutter.z': true});
  });

  test('a value over ksud limit is refused', () async {
    final store = SharedPreferencesWebUiStore(
      stock: InMemorySharedPreferencesStore.empty(),
      prefs: ModuleConfigPrefs(ksud({}).root()),
    );
    await expectLater(
      store.setValue('String', 'flutter.big', 'x' * (1024 * 1024)),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'webui-prefs-too-large',
        ),
      ),
    );
  });

  test('a browser tab uses the stock store without root', () async {
    final fake = ksud({});
    final stock = InMemorySharedPreferencesStore.empty();
    final store = SharedPreferencesWebUiStore(
      stock: stock,
      prefs: ModuleConfigPrefs(fake.root(FakeBridge.browser())),
    );
    await store.setValue('String', 'flutter.s', 'x');
    expect(await stock.getAll(), {'flutter.s': 'x'});
    expect(fake.runs, isEmpty);
  });

  test('the ksud wrapper sets KSU_MODULE in a real sh', () async {
    final fake = ksud({});
    await ModuleConfigPrefs(fake.root()).read();
    final run = fake.runs.single;
    final r = await Process.run('sh', [
      '-c',
      run.argv[2],
      'sh',
      run.shArgs[0],
      'sh',
      '-c',
      r'echo "$KSU_MODULE:$*"',
      'x',
      ...run.shArgs.skip(2),
    ]);
    expect(r.stdout, 'demo:module config get webui.shared_preferences\n');
  }, testOn: 'linux');
}
