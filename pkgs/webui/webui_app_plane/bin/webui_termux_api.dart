// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

// termux-api for webui-termux-api, run as root through the root channel:
//   webui_termux_api [--package <pkg>] [--wait <seconds>] <Method> [am extras...]
// stdin goes to the method, its answer to stdout. --wait sets how long the
// app may take to answer (default 10 s); methods that wait on the user, such
// as a permission dialog, pass more. flutter_p0g compiles this
// to <moddir>/webui_app_plane/<abi>/webui_termux_api.aot; module/termux-api
// runs it.

import 'dart:io';

import 'package:webui_app_plane/termux_api.dart';

Future<void> main(List<String> args) async {
  var package = termuxApiPackage;
  var rest = args;
  if (rest.length >= 2 && rest.first == '--package') {
    package = rest[1];
    rest = rest.sublist(2);
  }
  var wait = const Duration(seconds: 10);
  if (rest.length >= 2 && rest.first == '--wait') {
    final seconds = int.tryParse(rest[1]);
    if (seconds == null || seconds <= 0) {
      stderr.writeln('webui_termux_api: --wait takes a positive number');
      exit(64);
    }
    wait = Duration(seconds: seconds);
    rest = rest.sublist(2);
  }
  if (rest.isEmpty || rest.first.startsWith('-')) {
    stderr.writeln(
      'usage: webui_termux_api [--package <pkg>] [--wait <seconds>] '
      '<Method> [am extras...]',
    );
    exit(64);
  }
  try {
    await callTermuxApi(
      method: rest.first,
      extras: rest.sublist(1),
      input: stdin,
      output: stdout,
      package: package,
      connectTimeout: wait,
    );
    await stdout.flush();
    exit(0);
  } on TermuxApiException catch (e) {
    stderr.writeln('webui_termux_api: ${e.message}');
    exit(1);
  }
}
