// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

// A Dart port of the socket handling in termux-api.c (termux-api-package
// 9e7f153, `run_api_command` and `exec_am_broadcast_v2`): two listening
// abstract AF_UNIX sockets, an `am broadcast` naming them, then stdin to one
// and the other to stdout. The Termux:API contract is kept as is; the
// receiving side is webui-termux-api `util/ResultReturner.java`.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'termux_api_names.dart';

/// Runs `am` with [args]; the default is `/system/bin/am`.
typedef AmRunner = Future<ProcessResult> Function(List<String> args);

/// A call that did not complete.
final class TermuxApiException implements Exception {
  const TermuxApiException(this.message);

  final String message;

  @override
  String toString() => 'TermuxApiException: $message';
}

/// Calls one Termux:API [method] with am-style [extras], writing [input] to
/// the method and its answer to [output]. Completes when the app closes its
/// answer. Throws [TermuxApiException] when `am` fails or the app does not
/// connect within [connectTimeout].
Future<void> callTermuxApi({
  required String method,
  List<String> extras = const [],
  Stream<List<int>>? input,
  required StreamSink<List<int>> output,
  String package = termuxApiPackage,
  String receiver = termuxApiReceiver,
  AmRunner? am,
  Duration connectTimeout = const Duration(seconds: 10),
}) async {
  am ??= (args) => Process.run('/system/bin/am', args);
  // termux-api.c names: "input" is what this side reads (the app's output),
  // "output" what it writes (the app's input).
  final inputName = _socketName();
  final outputName = _socketName();
  final inputServer = await ServerSocket.bind(_abstract(inputName), 0);
  final outputServer = await ServerSocket.bind(_abstract(outputName), 0);
  try {
    // The app connects its output first, then its input only for methods
    // that read stdin (ResultReturner.returnData), so the input side runs on
    // its own and is never waited for.
    final feeding = outputServer.first.then((socket) async {
      try {
        if (input != null) await socket.addStream(input);
      } finally {
        await socket.close();
      }
    });
    unawaited(feeding.catchError((Object _) {}));

    final broadcast = am([
      'broadcast',
      '--user',
      '0',
      '-n',
      '$package/$receiver',
      // Reversed for the app: our output is its input (termux-api.c).
      '--es', 'socket_input', outputName,
      '--es', 'socket_output', inputName,
      '--ei', 'api_server_pid', '$pid',
      '--ei', 'api_server_uid', '${_uid() ?? -1}',
      '--ei', 'api_server_starttime', '${_startTime(pid) ?? -1}',
      '--es', 'api_method', method,
      ...extras,
    ]);

    final result = await broadcast;
    if (result.exitCode != 0) {
      throw TermuxApiException(
        'am broadcast exited ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
    // Connections wait in the listen backlog until accepted here.
    final socket = await inputServer.first.timeout(
      connectTimeout,
      onTimeout: () => throw TermuxApiException(
        '$package did not answer $method within ${connectTimeout.inSeconds} s '
        '(not installed, disabled, or the broadcast was refused)',
      ),
    );
    await output.addStream(socket);
    socket.destroy();
  } finally {
    await inputServer.close();
    await outputServer.close();
  }
}

InternetAddress _abstract(String name) =>
    InternetAddress('@$name', type: InternetAddressType.unix);

final Random _random = Random.secure();

/// A UUID-shaped random name, as termux-api.c `generate_uuid`.
String _socketName() {
  String hex(int digits) =>
      [for (var i = 0; i < digits; i++) _random.nextInt(16).toRadixString(16)]
          .join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-${hex(12)}';
}

int? _uid() {
  try {
    final line = File('/proc/self/status')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('Uid:'));
    return int.tryParse(line.split(RegExp(r'\s+'))[1]);
  } on Object {
    return null;
  }
}

/// Field 22 of `/proc/<pid>/stat`, as termux-api.c `get_process_starttime`.
int? _startTime(int pid) {
  try {
    final stat = File('/proc/$pid/stat').readAsStringSync();
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    return int.tryParse(fields[19]);
  } on Object {
    return null;
  }
}
