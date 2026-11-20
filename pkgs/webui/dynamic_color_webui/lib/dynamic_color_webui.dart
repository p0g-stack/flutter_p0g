// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// dynamic_color for WebUI hosts (`docs/plugins.md`).
library;

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_webui_client/web.dart';
import 'package:web/web.dart' as web;

import 'src/host_colors.dart';

/// Registers a web handler for dynamic_color's method channel. dynamic_color
/// is not federated and has no web implementation, so this answers its
/// channel directly and apps keep `DynamicColorBuilder` /
/// `DynamicColorPlugin` unchanged.
abstract final class DynamicColorWebUi {
  static DynamicColorWebUiHandler? _handler;

  /// Optional, beyond the stock API: the manager's own scheme for
  /// [brightness] as a Flutter [ColorScheme], with the host's exact role
  /// colours when its stylesheet is that brightness and the rest derived as
  /// dynamic_color does. Null in a browser tab, without colours, or before
  /// registration.
  static Future<ColorScheme?> hostColorScheme(Brightness brightness) async =>
      _handler?.colorScheme(brightness);

  static void registerWith(Registrar registrar) {
    final handler = _handler = DynamicColorWebUiHandler(
      host: WebUi.host,
      fetch: _fetchColorsCss,
    );
    MethodChannel(
      dynamicColorChannel,
      const StandardMethodCodec(),
      registrar,
    ).setMethodCallHandler(handler.handle);
  }

  static Future<String?> _fetchColorsCss() async {
    final response = await web.window
        .fetch('/internal/colors.css'.toJS, web.RequestInit(cache: 'no-store'))
        .toDart;
    if (!response.ok) return null;
    return (await response.text().toDart).toDart;
  }
}
