// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// path_provider for WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/path_provider_webui_impl.dart';

/// Registers the WebUI implementation of [PathProviderPlatform]. path_provider
/// has no stock web implementation, so this one is used even when it comes
/// in transitively.
abstract final class PathProviderWebUi {
  static void registerWith(Registrar registrar) {
    PathProviderPlatform.instance = PathProviderWebUiImpl(
      stock: PathProviderPlatform.instance,
      root: WebUiRoot.instance,
    );
  }
}
