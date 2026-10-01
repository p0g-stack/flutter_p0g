// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// Test doubles for the `*_webui` plugins: [FakeRootChannel], a root channel
/// that speaks the real v1 protocol (flutter-webui `docs/root-channel.md`) to
/// the real `RootChannel` client and answers each process from a script.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:flutter_webui_client/testing.dart';
import 'package:flutter_webui_root/protocol.dart';

import 'webui_app_plane.dart';

export 'package:flutter_webui_client/testing.dart' show FakeBridge;

/// What a scripted root process prints and how it exits.
final class FakeProcessResult {
  const FakeProcessResult({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// One process the page started: its argv and everything it got on stdin.
final class FakeRun {
  FakeRun(this.argv, this.stdin);

  final List<String> argv;
  final List<int> stdin;

  /// For `sh -c script sh args...`: the args after `sh`.
  List<String> get shArgs =>
      argv.length > 3 && argv[1] == '-c' ? argv.sublist(4) : const [];

  String get stdinText => utf8.decode(stdin, allowMalformed: true);

  @override
  String toString() => 'FakeRun($argv)';
}

/// Answers a process once its stdin is closed.
typedef FakeProcessHandler = FutureOr<FakeProcessResult> Function(FakeRun run);

/// A root channel for tests. Each started process is recorded in [runs] and
/// answered by [handler] once the page closes its stdin.
final class FakeRootChannel {
  FakeRootChannel({
    this.moduleDir = '/data/adb/modules/demo',
    FakeProcessHandler? handler,
  }) : handler = handler ?? ((_) => const FakeProcessResult());

  final String moduleDir;
  FakeProcessHandler handler;

  /// Processes started, in order.
  final List<FakeRun> runs = [];

  /// Set to make [connect] fail as an unreachable channel does.
  bool unavailable = false;

  /// Connects the real client to this fake: `root start` prints this
  /// fake's session, or fails while [unavailable].
  Future<RootChannel> connect() => RootChannel.connect(
    transport: _FakeTransport(this),
    start: () async => unavailable
        ? const ExecResult(1, '', 'root channel did not start')
        : ExecResult(
            0,
            '${jsonEncode(SessionInfo(protocol: protocolVersion, version: channelVersion, port: 1, token: 'test', pid: 1, boot: 'boot', started: DateTime.utc(2026)).toJson())}\n',
            '',
          ),
  );

  /// A [WebUiRoot] on [bridge] (KernelSU by default) using this channel.
  WebUiRoot root([FakeBridge? bridge]) => WebUiRoot(
    host: WebUiHost.detect(bridge ?? FakeBridge.kernelsu()),
    connect: connect,
  );
}

final class _FakeTransport implements ChannelTransport {
  _FakeTransport(this.fake);

  final FakeRootChannel fake;

  @override
  Future<ChannelSocket> connect(Uri uri) async => _FakeSocket(fake);
}

final class _FakeSocket implements ChannelSocket {
  _FakeSocket(this.fake) {
    _frames.add(
      jsonEncode({
        'op': 'hello',
        'protocol': protocolVersion,
        'version': channelVersion,
        'pid': 1,
        'boot': 'boot',
        'uid': 0,
        'moduleDir': fake.moduleDir,
      }),
    );
  }

  final FakeRootChannel fake;
  final StreamController<Object> _frames = StreamController();
  final Map<int, List<String>> _argv = {};
  final Map<int, BytesBuilder> _stdin = {};

  @override
  Stream<Object> get frames => _frames.stream;

  @override
  void sendText(String text) {
    final message = jsonDecode(text) as Map<String, Object?>;
    final id = message['id'] as int;
    switch (message['op']) {
      case 'start':
        _argv[id] = (message['argv'] as List).cast<String>();
        _stdin[id] = BytesBuilder();
        _frames.add(jsonEncode({'op': 'started', 'id': id, 'pid': 1000 + id}));
      case 'close-stdin':
        unawaited(_finish(id));
      case 'read':
        _frames.add(
          jsonEncode({
            'op': 'error',
            'id': id,
            'code': ErrorCode.notFound,
            'message': 'fake channel has no files',
          }),
        );
      default:
        break;
    }
  }

  Future<void> _finish(int id) async {
    final run = FakeRun(_argv[id]!, _stdin.remove(id)!.takeBytes());
    fake.runs.add(run);
    final result = await fake.handler(run);
    void data(int stream, String text) {
      if (text.isEmpty) return;
      _frames.add(DataFrame(stream, id, utf8.encode(text)).encode());
    }

    data(StreamTag.stdout, result.stdout);
    data(StreamTag.stderr, result.stderr);
    _frames.add(jsonEncode({'op': 'exit', 'id': id, 'code': result.exitCode}));
  }

  @override
  void sendBytes(Uint8List bytes) {
    final frame = DataFrame.decode(bytes);
    if (frame != null && frame.stream == StreamTag.stdin) {
      _stdin[frame.id]?.add(frame.payload);
    }
  }

  @override
  Future<void> close() async {
    if (!_frames.isClosed) await _frames.close();
  }
}
