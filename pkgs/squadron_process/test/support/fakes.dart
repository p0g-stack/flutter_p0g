import 'dart:async';

import 'package:squadron/squadron.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';

import 'echo_service.dart';

/// A launcher that "starts" a host by creating a [PlaceHost] in memory and
/// printing its ready line, the way the CLI does.
class FakeLauncher implements ProcessLauncher {
  final hosts = <int, PlaceHost>{};
  final commands = <ProcessCommand>[];
  int _nextPort = 4000;
  bool silent = false;
  bool stdoutVisible = true;
  final endpoints = <ProcessEndpoint>[];

  @override
  Future<LaunchedProcess> launch(ProcessCommand command) async {
    commands.add(command);
    final port = _nextPort++;
    final token = 'token-$port';
    hosts[port] = PlaceHost(
      services: {'echo': EchoWorker()},
      token: token,
      checkFacts: () async => PlaceFacts({'root': true, 'port': port}),
    );
    final launchId = command.arguments.last;
    endpoints.add(
      ProcessEndpoint(port: port, token: token, pid: port, launchId: launchId),
    );
    final lines = StreamController<String>();
    if (!silent && stdoutVisible) {
      lines.add('some log line before the ready line');
      lines.add(endpoints.last.encode());
    }
    if (!stdoutVisible) lines.close();
    return _Launched(port, lines.stream);
  }

  Future<PlaceLink> connect(ProcessEndpoint e) async {
    final host = hosts[e.port];
    if (host == null || host.isDone) {
      throw StateError('connection refused');
    }
    final (client, server) = PlaceLink.pair();
    host.accept(server);
    return client;
  }

  Future<void> dispose() async {
    for (final h in hosts.values) {
      await h.shutdown();
      (h.services.values.single as Worker).stop();
    }
  }
}

class _Launched implements LaunchedProcess {
  _Launched(this.pid, this.stdoutLines);
  @override
  final int? pid;
  @override
  final Stream<String> stdoutLines;
  @override
  Future<int> get exitCode => Completer<int>().future;
}

class FakeStore implements EndpointStore {
  ProcessEndpoint? endpoint;
  @override
  Future<ProcessEndpoint?> read() async => endpoint;
}
