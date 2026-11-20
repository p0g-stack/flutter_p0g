// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// url_launcher for WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_web/url_launcher_web.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/url_launcher_webui_impl.dart';

/// Registers the WebUI implementation of [UrlLauncherPlatform].
///
/// When this package is a direct dependency, Flutter registers it instead of
/// `url_launcher_web`, so this runs the stock registration first (it also
/// registers the `Link` platform view) and wraps what it installed.
abstract final class UrlLauncherWebUi {
  static void registerWith(Registrar registrar) {
    UrlLauncherPlugin.registerWith(registrar);
    UrlLauncherPlatform.instance = UrlLauncherWebUiImpl(
      stock: UrlLauncherPlatform.instance,
      root: WebUiRoot.instance,
    );
  }
}
