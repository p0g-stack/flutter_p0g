// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:flutter_webui/flutter_webui.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// The browser clipboard first, the module's app when the WebView refuses.
///
/// WebView always refuses `navigator.clipboard.readText` (flutter-webui
/// docs/parity.md), so reads come from the app's `Clipboard` method, which
/// reads from an invisible focused activity on Android 10+ (webui.6).
/// Writes normally succeed in the browser (WebView grants them); the app
/// covers a refused one.
final class AppPlaneClipboard implements TextClipboard {
  AppPlaneClipboard({required this.plane, required this.browser});

  final AppPlane plane;

  /// The embedding's browser clipboard, looked up per call (it installs
  /// after this plugin registers).
  final TextClipboard? Function() browser;

  /// How long a read may take: the activity has to start and get focus.
  static const Duration readWait = Duration(seconds: 30);

  @override
  Future<String?> getText() async {
    final b = browser();
    if (b != null) {
      try {
        return await b.getText();
      } on Object {
        if (!await plane.isAvailable()) rethrow;
      }
    }
    final r = await _call(['--es', 'api_version', '2'], wait: readWait);
    return r.text;
  }

  @override
  Future<void> setText(String text) async {
    final b = browser();
    if (b != null) {
      try {
        return await b.setText(text);
      } on Object {
        if (!await plane.isAvailable()) rethrow;
      }
    }
    await _call([
      '--es',
      'api_version',
      '2',
      '--ez',
      'set',
      'true',
    ], input: utf8.encode(text));
  }

  Future<RootResult> _call(
    List<String> extras, {
    List<int>? input,
    Duration? wait,
  }) async {
    try {
      return await plane.call(
        'Clipboard',
        extras: extras,
        input: input,
        wait: wait,
      );
    } on AppPlaneException catch (e) {
      // The engine turns this into its paste_fail / set error envelope.
      throw StateError('Clipboard via ${plane.package}: ${e.message}');
    }
  }
}
