import 'dart:convert';

/// Where a running place host can be reached.
class ProcessEndpoint {
  const ProcessEndpoint({
    required this.port,
    required this.token,
    this.pid,
    this.launchId,
    this.host = '127.0.0.1',
  });

  final String host;
  final int port;
  final String token;
  final int? pid;

  /// The `--launch-id` the host was started with, if any.
  final String? launchId;

  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: '/squadron');

  /// The ready line a host prints on stdout and the session file it writes
  /// share this JSON shape: `{"squadron_process":1,"port":..,"token":..,"pid":..}`.
  Map<String, Object?> toJson() => {
    'squadron_process': 1,
    'host': host,
    'port': port,
    'token': token,
    if (pid != null) 'pid': pid,
    if (launchId != null) 'launch_id': launchId,
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
        launchId: m['launch_id'] as String?,
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

  ProcessCommand withArguments(List<String> arguments) => ProcessCommand(
    executable,
    arguments: arguments,
    environment: environment,
    workingDirectory: workingDirectory,
  );

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

/// Starts place hosts. Implementations are siblings, one per way of starting
/// a process; `package:squadron_process/io.dart` has a plain one
/// (`IoProcessLauncher`) and one per OS elevation front-end
/// (`ElevatedLauncher`). An embedding with its own way of starting processes
/// (a privileged helper, a remote shell, a sandbox broker) implements this
/// interface; docs/launchers.md says what it must do.
///
/// The process must be started detached: it has to outlive the client's link
/// (a client restart, the launcher's own shell going away) and stop only by
/// the host's lifetime rule.
abstract interface class ProcessLauncher {
  Future<LaunchedProcess> launch(ProcessCommand command);
}

/// Finds a host that is already running, so a restarted client reattaches to
/// the same process instead of starting another one, and so a launcher that
/// cannot see the host's stdout can still find it. Reads what the host wrote to
/// its session file (`serve --session-file`).
abstract interface class EndpointStore {
  /// The last endpoint the host published, or null if there is none.
  Future<ProcessEndpoint?> read();
}
