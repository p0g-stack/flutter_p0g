import 'dart:convert';

/// Where a running place host can be reached.
class ProcessEndpoint {
  const ProcessEndpoint({
    required this.port,
    required this.token,
    this.pid,
    this.host = '127.0.0.1',
  });

  final String host;
  final int port;
  final String token;
  final int? pid;

  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/squadron');

  /// The ready line a host prints on stdout and the session file it writes
  /// share this JSON shape: `{"squadron_process":1,"port":..,"token":..,"pid":..}`.
  Map<String, Object?> toJson() => {
    'squadron_process': 1,
    'host': host,
    'port': port,
    'token': token,
    if (pid != null) 'pid': pid,
  };

  String encode() => jsonEncode(toJson());

  /// Parses a ready line or session file; null if [text] is not one.
  static ProcessEndpoint? tryParse(String text) {
    try {
      final m = jsonDecode(text);
      if (m is! Map || m['squadron_process'] != 1) return null;
      final port = m['port'], token = m['token'];
      if (port is! int || token is! String || token.isEmpty) return null;
      return ProcessEndpoint(
        host: (m['host'] as String?) ?? '127.0.0.1',
        port: port,
        token: token,
        pid: m['pid'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'ProcessEndpoint($host:$port, pid $pid)';
}

/// The command that starts a place host: the app's own CLI in serve mode.
class ProcessCommand {
  const ProcessCommand(
    this.executable, {
    this.arguments = const ['serve'],
    this.environment = const {},
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}

/// A started host process, as far as the launcher can see it.
abstract interface class LaunchedProcess {
  int? get pid;

  /// stdout split into lines. The host's first line is its ready line.
  Stream<String> get stdoutLines;

  /// Completes with the exit code if the process exits.
  Future<int> get exitCode;
}

/// Starts place hosts. squadron_process does not know how a platform starts
/// processes; each platform supplies one of these:
///
/// - desktop and tests: `IoProcessLauncher` (`package:squadron_process/io.dart`);
/// - WebUI: an adapter over flutter-webui's root channel, wired in by the
///   `p0g_app` brick (see docs/webui-launch.md for what it must provide).
///
/// The process must be started detached: it has to outlive the caller's link
/// (a page reload, a manager closing its shell) and stop only by the lifetime
/// rule.
abstract interface class ProcessLauncher {
  Future<LaunchedProcess> launch(ProcessCommand command);
}

/// Finds a host that is already running, so a reloaded page reattaches to the
/// same process instead of starting another one. Reads what the host wrote to
/// its session file (`serve --session-file`).
abstract interface class EndpointStore {
  /// The last endpoint the host published, or null if there is none.
  Future<ProcessEndpoint?> read();
}
