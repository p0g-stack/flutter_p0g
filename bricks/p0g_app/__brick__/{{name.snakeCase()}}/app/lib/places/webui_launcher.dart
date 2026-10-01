import 'package:squadron_process/squadron_process.dart';

/// What the WebUI launcher needs from flutter-webui's page client
/// (`package:flutter_webui`: `WebUi.host.moduleDir`, `WebUi.connectRootChannel`,
/// `RootChannel.start` / `read`, `RootProcess.lines` / `exitCode`; root
/// channel contract v1).
///
/// The app does not depend on flutter_webui itself: it is a web plugin that
/// needs flutter-webui's patched web engine, so a stock `flutter build web`
/// would not compile. The WebUI target sets [webUiRoot] from its own glue,
/// a small adapter over those calls.
abstract interface class WebUiRoot {
  /// The module directory on the device.
  String get moduleDir;

  /// Starts [argv] through the root channel, as root.
  Future<WebUiRootProcess> start(
    List<String> argv, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool detached = false,
  });

  /// Reads a small UTF-8 file inside the module directory.
  Future<String> read(String path);
}

abstract interface class WebUiRootProcess {
  int get pid;

  /// stdout as lines; for a detached process its log, ready line first.
  Stream<String> get lines;

  Future<int> get exitCode;
}

/// Set on a WebUI host before the app builds its places.
WebUiRoot? webUiRoot;

/// The process place on WebUI: `<module>/bin/<app> serve`, started detached
/// as root through the root channel, and found again after a reload through
/// its session file. The contract is docs/webui-launch.md in p0g-stack/bricks.
ProcessPlace webUiProcessPlace(WebUiRoot root, {required String app}) {
  final session = '${root.moduleDir}/webroot/.run/$app.place.json';
  return ProcessPlace(
    launcher: WebUiLauncher(root),
    store: WebUiSessionStore(root, session),
    // flutter_p0g ships `bin/<app>`, a launcher that runs the CLI's AOT
    // snapshot with `<abi>/dartaotruntime`.
    command: ProcessCommand(
      '${root.moduleDir}/bin/$app',
      arguments: ['serve', '--session-file', session],
    ),
  );
}

/// Starts a place host through the root channel: detached, as root, with the
/// command exactly as `ProcessPlace` built it (including `--launch-id`).
final class WebUiLauncher implements ProcessLauncher {
  const WebUiLauncher(this.root);

  final WebUiRoot root;

  @override
  Future<LaunchedProcess> launch(ProcessCommand command) async {
    final p = await root.start(
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

  final WebUiRootProcess _p;

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

  final WebUiRoot root;
  final String path;

  @override
  Future<ProcessEndpoint?> read() async {
    try {
      return ProcessEndpoint.tryParse(await root.read(path));
    } on Object {
      return null;
    }
  }
}
