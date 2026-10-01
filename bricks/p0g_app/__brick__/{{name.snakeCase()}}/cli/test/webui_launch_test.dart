@TestOn('linux || mac-os')
library;

import 'dart:convert';
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

    // `root start` in-process: start the channel once and print its session.
    Future<ExecResult> rootStart() async {
      server ??= await RootChannelServer.start(
        moduleDir: module,
        runDir: Directory('${module.path}/flutter_webui/run'),
        store: SessionStore(_MemoryConfig()),
      );
      return ExecResult(0, '${jsonEncode(server!.info.toJson())}\n', '');
    }

    Future<RootChannel> connect() async => channel = await RootChannel.connect(
      transport: IoChannelTransport(origin: managerOrigin),
      start: rootStart,
    );

    final place = webUiProcessPlace(
      connect,
      moduleDir: module.path,
      app: '{{name.snakeCase()}}',
    );
    final lines = <String>[];
    addTearDown(logTo(lines.add, level: Level.ALL));
    final worker = place.bind(
      withLogs(HelloServiceWorker()),
      service: 'hello',
    );
    addTearDown(worker.terminate);
    // A second link from this page: records still arrive once.
    final other = place.bind(
      withLogs(HelloServiceWorker()),
      service: 'hello',
    );
    addTearDown(other.terminate);
    expect(await other.hello('other'), 'Hello, other!');
    expect(await worker.hello('webui'), 'Hello, webui!');
    // The service's own log record, relayed from the host process.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      lines.where((l) => l.endsWith('FINE service.hello: hello webui')),
      hasLength(1),
    );
    expect(await worker.count(2).toList(), [1, 2]);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// tmp.config in memory, in place of `ksud module config`.
final class _MemoryConfig implements ModuleConfig {
  final _temp = <String, String>{};

  @override
  Future<String?> get(String key) async => _temp[key];

  @override
  Future<void> setTemp(String key, String value) async => _temp[key] = value;

  @override
  Future<void> deleteTemp(String key) async => _temp.remove(key);
}
