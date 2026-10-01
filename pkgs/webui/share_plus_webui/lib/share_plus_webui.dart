// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// share_plus for WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
// The web class is exported only under dart.library.js_interop.
// ignore: implementation_imports
import 'package:share_plus/src/share_plus_web.dart' show SharePlusWebPlugin;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_web/url_launcher_web.dart';
// ignore: implementation_imports
import 'package:url_launcher_webui/src/url_launcher_webui_impl.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/share_plus_webui_impl.dart';

/// Registers the WebUI implementation of [SharePlatform].
///
/// share_plus carries its web implementation inline; when this package is a
/// direct dependency Flutter registers it instead, so it builds the stock one
/// itself, with the WebUI url_launcher for its `mailto:` fallback.
abstract final class SharePlusWebUi {
  static void registerWith(Registrar registrar) {
    final root = WebUiRoot.instance;
    SharePlatform.instance = SharePlusWebUiImpl(
      stock: SharePlusWebPlugin(
        UrlLauncherWebUiImpl(stock: UrlLauncherPlugin(), root: root),
      ),
      plane: AppPlane(root),
    );
  }
}
