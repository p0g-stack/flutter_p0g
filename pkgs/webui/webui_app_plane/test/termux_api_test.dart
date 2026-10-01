// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

@TestOn('linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:webui_app_plane/termux_api.dart';

/// Plays webui-termux-api's side (util/ResultReturner.java): reads the
/// extras, connects socket_output (the answer), then socket_input for
/// methods that take stdin.
AmRunner fakeApp({
  required void Function(List<String> args) onBroadcast,
  bool readsInput = true,
  String Function(String input)? answer,
  int amExit = 0,
  bool connect = true,
}) => (args) async {
  onBroadcast(args);
  String extra(String name) => args[args.indexOf(name) + 1];
  InternetAddress addr(String name) =>
      InternetAddress('@${extra(name)}', type: InternetAddressType.unix);
  if (connect) {
    unawaited(() async {
      final out = await Socket.connect(addr('socket_output'), 0);
      var input = '';
      if (readsInput) {
        final inp = await Socket.connect(addr('socket_input'), 0);
        input = await utf8.decodeStream(inp);
        inp.destroy();
      }
      out.add(utf8.encode((answer ?? (i) => 'ok:$i')(input)));
      await out.close();
    }());
  }
  return ProcessResult(1, amExit, '', amExit == 0 ? '' : 'Error: boom');
};

Future<String> call(
  AmRunner am, {
  String method = 'Clipboard',
  List<String> extras = const [],
  String? input,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final out = StreamController<List<int>>();
  final text = utf8.decodeStream(out.stream);
  await callTermuxApi(
    method: method,
    extras: extras,
    input: input == null ? null : Stream.value(utf8.encode(input)),
    output: out,
    am: am,
    connectTimeout: timeout,
  );
  await out.close();
  return text;
}

void main() {
  test('broadcasts like termux-api.c and pipes stdin and stdout', () async {
    late List<String> args;
    final text = await call(
      fakeApp(onBroadcast: (a) => args = a),
      method: 'Share',
      extras: ['--es', 'action', 'send'],
      input: 'hello',
    );
    expect(text, 'ok:hello');
    expect(args.take(5), [
      'broadcast',
      '--user',
      '0',
      '-n',
      'com.webui.termux.api/com.termux.api.TermuxApiReceiver',
    ]);
    String extra(String name) => args[args.indexOf(name) + 1];
    expect(extra('api_method'), 'Share');
    expect(extra('api_server_pid'), '$pid');
    expect(int.parse(extra('api_server_uid')), greaterThanOrEqualTo(0));
    expect(extra('socket_input'), isNot(extra('socket_output')));
    expect(args.sublist(args.length - 3), ['--es', 'action', 'send']);
  });

  test('a method without input answers without its input socket', () async {
    final text = await call(
      fakeApp(onBroadcast: (_) {}, readsInput: false, answer: (_) => '{"a":1}'),
      method: 'BatteryStatus',
      input: 'ignored',
    );
    expect(text, '{"a":1}');
  });

  test('a failed am is reported', () async {
    await expectLater(
      call(fakeApp(onBroadcast: (_) {}, amExit: 1, connect: false)),
      throwsA(
        isA<TermuxApiException>().having(
          (e) => e.message,
          'message',
          contains('boom'),
        ),
      ),
    );
  });

  test('an app that never connects times out', () async {
    await expectLater(
      call(
        fakeApp(onBroadcast: (_) {}, connect: false),
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(
        isA<TermuxApiException>().having(
          (e) => e.message,
          'message',
          contains('did not answer Clipboard'),
        ),
      ),
    );
  });
}
