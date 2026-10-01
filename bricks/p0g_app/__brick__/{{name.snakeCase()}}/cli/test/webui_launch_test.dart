@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_webui_client/flutter_webui_client.dart';
// The page's dart:io transport; a WebUI page uses the browser one.
// ignore: implementation_imports
import 'package:flutter_webui_client/src/io_transport.dart';
import 'package:flutter_webui_root/flutter_webui_root.dart';
import 'package:test/test.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// The WebUI launch (docs/webui-launch.md) through flutter-webui's real root
/// channel: the page side connects to `flutter_webui_root`, which starts
/// `<module>/bin/{{name.snakeCase()}} serve` detached. Here bin/{{name.snakeCase()}} runs the CLI
/// from source instead of the AOT snapshot flutter_p0g ships.
void main() {
  test('hello runs in the CLI launched through the root channel', () async {
    final module = await Directory.systemTemp.createTemp('p0g_module');
    RootChannelServer? server;
    RootChannel? channel;
    addTearDown(() async {
      await channel?.close();
      await server?.shutdown();
      await module.delete(recursive: true);
    });
    final cli = File('bin/{{name.snakeCase()}}.dart').absolute.path;
    final bin = File('${module.path}/bin/{{name.snakeCase()}}');
    await bin.create(recursive: true);
    await bin.writeAsString(
      '#!/bin/sh\n'
      'cd "${Directory.current.path}"\n'
      'exec "${Platform.resolvedExecutable}" run "$cli" "\$@" --grace-ms 200\n',
    );
    await Process.run('chmod', ['+x', bin.path]);

    Future<RootChannel> connect() async => channel = await RootChannel.connect(
      transport: IoChannelTransport(
        File('${module.path}/webroot/.run/session.json'),
        origin: managerOrigin,
      ),
      start: () async =>
          server ??= await RootChannelServer.start(moduleDir: module),
    );

    final place = webUiProcessPlace(
      connect,
      moduleDir: module.path,
      app: '{{name.snakeCase()}}',
    );
    final worker = place.bind(HelloServiceWorker(), service: 'hello');
    addTearDown(worker.terminate);
    expect(await worker.hello('webui'), 'Hello, webui!');
    expect(await worker.count(2).toList(), [1, 2]);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
