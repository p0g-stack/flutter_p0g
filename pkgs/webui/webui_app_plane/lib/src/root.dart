// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webui_client/flutter_webui_client.dart';

/// Opens (or reuses) the root channel connection.
typedef RootChannelConnector = Future<RootChannel> Function();

/// What a plugin needs from the host: [host] and root commands through the
/// flutter-webui root channel (`docs/root-channel.md` in flutter-webui).
final class WebUiRoot {
  WebUiRoot({required this.host, required this.connect});

  static WebUiRoot? _instance;

  /// The page's host, from `flutter_webui_client`.
  static WebUiRoot get instance => _instance ??= WebUiRoot(
    host: WebUi.host,
    connect: WebUi.connectRootChannel,
  );

  /// Replaces [instance]; for tests.
  static set instance(WebUiRoot root) => _instance = root;

  final WebUiHost host;

  /// Opens or reuses the root channel connection.
  final RootChannelConnector connect;

  /// Whether the root channel can exist here: a WebUI host with `ksu.exec`
  /// and a known module directory. A browser tab is never one.
  bool get available =>
      host.isWebUi &&
      host.moduleDir != null &&
      host.ksuMethods.contains('exec');

  /// The module directory (`/data/adb/modules/<id>`); null in a browser tab.
  String? get moduleDir => host.moduleDir;

  /// The module id; null in a browser tab.
  String? get moduleId => host.moduleId;

  /// The root channel connection.
  Future<RootChannel> channel() => connect();

  /// Runs [argv] as root, feeds it [stdin] (or nothing) and collects its
  /// output. Never throws for a non-zero exit; throws [RootChannelException]
  /// when the channel is unavailable or the process cannot start.
  Future<RootResult> run(List<String> argv, {List<int>? stdin}) async {
    final channel = await connect();
    final process = await channel.start(argv);
    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    final reading = Future.wait([
      process.stdout.forEach(out.add),
      process.stderr.forEach(err.add),
    ]);
    if (stdin != null && stdin.isNotEmpty) process.stdin.add(stdin);
    unawaited(process.stdin.close());
    final code = await process.exitCode;
    await reading;
    return RootResult(code, out.takeBytes(), err.takeBytes());
  }

  /// Runs a POSIX sh [script] as root. Extra [args] are `$1`, `$2`, ...; pass
  /// every value that comes from outside as an argument, never inside
  /// [script].
  Future<RootResult> sh(
    String script, {
    List<String> args = const [],
    List<int>? stdin,
  }) => run(['/system/bin/sh', '-c', script, 'sh', ...args], stdin: stdin);
}

/// Output of one root command.
final class RootResult {
  const RootResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final Uint8List stdout;
  final Uint8List stderr;

  bool get ok => exitCode == 0;

  /// stdout as UTF-8.
  String get text => utf8.decode(stdout, allowMalformed: true);

  /// stderr as UTF-8.
  String get errorText => utf8.decode(stderr, allowMalformed: true);

  @override
  String toString() =>
      'RootResult($exitCode, ${text.trim()}, ${errorText.trim()})';
}
