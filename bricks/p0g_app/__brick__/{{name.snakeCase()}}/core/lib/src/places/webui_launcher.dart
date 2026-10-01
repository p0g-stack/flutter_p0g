import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:squadron_process/squadron_process.dart';

/// The process place on WebUI: `<module>/bin/<app> serve`, started detached
/// as root through flutter-webui's root channel, and found again after a
/// reload through its session file. The contract is docs/webui-launch.md in
/// p0g-stack/bricks.
///
/// [connect] opens the root channel; on a WebUI page that is
/// `WebUi.connectRootChannel`. It is called again when the channel closed.
ProcessPlace webUiProcessPlace(
  Future<RootChannel> Function() connect, {
  required String moduleDir,
  required String app,
}) {
  final root = RootChannelConnection(connect);
  final session = '$moduleDir/webroot/.run/$app.place.json';
  return ProcessPlace(
    launcher: WebUiLauncher(root),
    store: WebUiSessionStore(root, session),
    // flutter_p0g ships `bin/<app>`, a launcher that runs the CLI's AOT
    // snapshot with `<abi>/dartaotruntime`.
    command: ProcessCommand(
      '$moduleDir/bin/$app',
      arguments: ['serve', '--session-file', session],
    ),
  );
}

/// One root channel, opened on first use and again after it closed.
final class RootChannelConnection {
  RootChannelConnection(this._connect);

  final Future<RootChannel> Function() _connect;
  Future<RootChannel>? _channel;

  Future<RootChannel> get channel async {
    final pending = _channel;
    if (pending != null) {
      try {
        final open = await pending;
        if (!open.isClosed) return open;
      } on Object {
        // Connect again below.
      }
    }
    return _channel = _connect();
  }
}

/// Starts a place host through the root channel: detached, as root, with the
/// command exactly as `ProcessPlace` built it (including `--launch-id`).
final class WebUiLauncher implements ProcessLauncher {
  const WebUiLauncher(this.root);

  final RootChannelConnection root;

  @override
  Future<LaunchedProcess> launch(ProcessCommand command) async {
    final channel = await root.channel;
    final p = await channel.start(
      [command.executable, ...command.arguments],
      workingDirectory: command.workingDirectory,
      environment: command.environment.isEmpty ? null : command.environment,
      detached: true,
    );
    return _Launched(p);
  }
}

final class _Launched implements LaunchedProcess {
  _Launched(this._p);

  final RootProcess _p;

  @override
  int? get pid => _p.pid;

  @override
  late final Stream<String> stdoutLines = _p.lines.asBroadcastStream();

  @override
  Future<int> get exitCode => _p.exitCode;
}

/// Reads the host's session file through the root channel, so the token never
/// sits on the manager's HTTP origin.
final class WebUiSessionStore implements EndpointStore {
  const WebUiSessionStore(this.root, this.path);

  final RootChannelConnection root;
  final String path;

  @override
  Future<ProcessEndpoint?> read() async {
    try {
      final channel = await root.channel;
      return ProcessEndpoint.tryParse(await channel.read(path));
    } on Object {
      return null;
    }
  }
}
