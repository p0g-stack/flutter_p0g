import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:{{name.snakeCase()}}/places/webui_launcher.dart';

final class FakeRoot implements WebUiRoot {
  final started = <List<String>>[];
  final files = <String, String>{};

  @override
  String get moduleDir => '/data/adb/modules/app';

  @override
  Future<WebUiRootProcess> start(
    List<String> argv, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool detached = false,
  }) async {
    expect(detached, isTrue);
    started.add(argv);
    return FakeProcess();
  }

  @override
  Future<String> read(String path) async =>
      files[path] ?? (throw StateError('no $path'));
}

final class FakeProcess implements WebUiRootProcess {
  @override
  int get pid => 42;

  @override
  Stream<String> get lines => Stream.fromIterable([
    '{"squadron_process":1,"port":40111,"token":"t","pid":43}',
  ]);

  @override
  Future<int> get exitCode => Completer<int>().future;
}

void main() {
  test('starts the CLI detached with the command as built', () async {
    final root = FakeRoot();
    final launched = await WebUiLauncher(root).launch(
      const ProcessCommand(
        '/data/adb/modules/app/bin/app',
        arguments: ['serve', '--launch-id', 'x'],
      ),
    );
    expect(root.started.single, [
      '/data/adb/modules/app/bin/app',
      'serve',
      '--launch-id',
      'x',
    ]);
    final ready = ProcessEndpoint.tryParse(await launched.stdoutLines.first);
    expect(ready?.port, 40111);
  });

  test('finds a running host through its session file', () async {
    final root = FakeRoot();
    const path = '/data/adb/modules/app/webroot/.run/app.place.json';
    final store = WebUiSessionStore(root, path);
    expect(await store.read(), isNull);
    root.files[path] = '{"squadron_process":1,"port":1,"token":"t"}';
    expect((await store.read())?.port, 1);
  });

  test('the place uses the module layout', () {
    final place = webUiProcessPlace(FakeRoot(), app: 'app');
    expect(place.command?.executable, '/data/adb/modules/app/bin/app');
    expect(place.command?.arguments, [
      'serve',
      '--session-file',
      '/data/adb/modules/app/webroot/.run/app.place.json',
    ]);
  });
}
