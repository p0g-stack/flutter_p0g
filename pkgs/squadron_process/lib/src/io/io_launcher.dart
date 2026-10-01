import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../launcher.dart';
import 'elevated.dart';

/// Starts a place host with `dart:io`, detached from this process but with
/// its stdio piped so the ready line can be read, with the caller's rights.
/// Elevation goes through an [ElevatedLauncher] instead.
class IoProcessLauncher implements ProcessLauncher {
  const IoProcessLauncher();

  @override
  Future<LaunchedProcess> launch(ProcessCommand command) async {
    final p = await Process.start(
      command.executable,
      command.arguments,
      environment: command.environment,
      workingDirectory: command.workingDirectory,
      mode: ProcessStartMode.detachedWithStdio,
    );
    // detachedWithStdio has no exit code; stderr is drained so the child
    // never blocks on a full pipe.
    p.stderr.drain<void>();
    return _IoLaunched(p);
  }
}

class _IoLaunched implements LaunchedProcess {
  _IoLaunched(this._p);

  final Process _p;

  @override
  int? get pid => _p.pid;

  @override
  late final Stream<String> stdoutLines = _p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();

  /// Never completes: a detached process cannot be waited on. A host that
  /// dies before its ready line shows up as stdout closing instead.
  @override
  Future<int> get exitCode => Completer<int>().future;
}

/// Reads the session file a host wrote with `serve --session-file`.
class FileEndpointStore implements EndpointStore {
  const FileEndpointStore(this.path);

  final String path;

  @override
  Future<ProcessEndpoint?> read() async {
    try {
      return ProcessEndpoint.tryParse(await File(path).readAsString());
    } catch (_) {
      return null;
    }
  }
}
