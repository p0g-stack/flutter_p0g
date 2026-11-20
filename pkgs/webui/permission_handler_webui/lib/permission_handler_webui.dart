// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// permission_handler for WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:permission_handler_html/permission_handler_html.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/permission_handler_webui_impl.dart';

/// Registers the WebUI implementation of [PermissionHandlerPlatform].
///
/// When this package is a direct dependency, Flutter registers it instead of
/// `permission_handler_html`, so this runs the stock registration first and
/// wraps what it installed: a browser tab keeps the browser's own prompts.
abstract final class PermissionHandlerWebUi {
  static void registerWith(Registrar registrar) {
    WebPermissionHandler.registerWith(registrar);
    PermissionHandlerPlatform.instance = PermissionHandlerWebUiImpl(
      stock: PermissionHandlerPlatform.instance,
      plane: AppPlane(WebUiRoot.instance),
    );
  }
}
