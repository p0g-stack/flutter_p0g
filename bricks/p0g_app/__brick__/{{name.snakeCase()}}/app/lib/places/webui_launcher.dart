import 'dart:convert';

import 'package:squadron_process/squadron_process.dart';

/// The parts of flutter-webui's page client (`RootChannel`, root channel
/// contract v1 in flutter-webui's docs/root-channel.md) that the WebUI launcher uses.
/// `RootChannel` from `package:flutter_webui` satisfies it once published;
/// until then nothing sets [rootChannel], and WebUI runs services in Web
/// Workers only.
abstract interface class RootChannelClient {
  /// The module directory, from the channel's hello.
  String get moduleDir;

  Future<RootProcessHandle> start(
    List<String> argv, {
    Map<String, String>? env,
    bool detached = false,
  });

  /// Reads a small UTF-8 file under the module directory.
  Future<String> read(String path);
}

abstract interface class RootProcessHandle {
  int? get pid;
  Stream<List<int>> get stdout;
  Future<int> get exitCode;
}

/// Set by main() on WebUI once the root channel is connected.
RootChannelClient? rootChannel;

/// The process place for [service] on WebUI:
/// `<module>/bin/<app> serve <service>`, started detached as root, and
/// found again after a reload through its session file. The contract is
/// docs/webui-launch.md in p0g-stack/bricks.
ProcessPlace webUiProcessPlace(
  RootChannelClient channel,
  String app,
  String service,
) {
  final dir = channel.moduleDir;
  final session = '$dir/webroot/.run/$app.$service.place.json';
  return ProcessPlace(
    launcher: WebUiLauncher(channel),
    store: WebUiSessionStore(channel, session),
    // flutter_p0g ships `bin/<app>`, a launcher that runs the CLI's AOT
    // snapshot with `<abi>/dartaotruntime`.
    command: ProcessCommand(
      '$dir/bin/$app',
      arguments: ['serve', service, '--session-file', session],
    ),
  );
}

/// Starts a place host through the root channel: detached, as root.
final class WebUiLauncher implements ProcessLauncher {
  const WebUiLauncher(this.channel);

  final RootChannelClient channel;

  @override
  Future<LaunchedProcess> launch(ProcessCommand command) async {
    final p = await channel.start(
      [command.executable, ...command.arguments],
      env: command.environment.isEmpty ? null : command.environment,
      detached: true,
    );
    return _Launched(p);
  }
}

final class _Launched implements LaunchedProcess {
  _Launched(this._p);

  final RootProcessHandle _p;

  @override
  int? get pid => _p.pid;

  @override
  late final Stream<String> stdoutLines = _p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();

  @override
  Future<int> get exitCode => _p.exitCode;
}

/// Reads the host's session file through the root channel, so the token never
/// sits on the manager's HTTP origin.
final class WebUiSessionStore implements EndpointStore {
  const WebUiSessionStore(this.channel, this.path);

  final RootChannelClient channel;
  final String path;

  @override
  Future<ProcessEndpoint?> read() async {
    try {
      return ProcessEndpoint.tryParse(await channel.read(path));
    } on Object {
      return null;
    }
  }
}
