// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// Stock `Clipboard` on WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_webui/flutter_webui.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/clipboard_webui_impl.dart';

/// Makes the engine clipboard on WebUI hosts fall back to the module's app.
///
/// `Clipboard.setData` and `Clipboard.getData` go to the engine, not to a
/// plugin channel, so this installs through flutter-webui's
/// [WebUiClipboard] instead of a platform interface. A browser tab keeps
/// the browser's clipboard.
abstract final class ClipboardWebUi {
  static void registerWith(Registrar registrar) {
    final root = WebUiRoot.instance;
    if (!root.available) return;
    WebUiClipboard.use(
      AppPlaneClipboard(
        plane: AppPlane(root),
        browser: () => WebUiClipboard.browser,
      ),
    );
  }
}
