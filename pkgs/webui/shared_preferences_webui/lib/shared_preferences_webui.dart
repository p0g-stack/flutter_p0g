// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// shared_preferences for WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/shared_preferences_webui_impl.dart';

/// Registers the WebUI implementations of [SharedPreferencesStorePlatform]
/// (`SharedPreferences`) and [SharedPreferencesAsyncPlatform]
/// (`SharedPreferencesAsync`, `SharedPreferencesWithCache`).
///
/// When this package is a direct dependency, Flutter registers it instead of
/// `shared_preferences_web`, so this runs the stock registration first and
/// wraps what it installed: a browser tab keeps localStorage.
abstract final class SharedPreferencesWebUi {
  static void registerWith(Registrar registrar) {
    SharedPreferencesPlugin.registerWith(registrar);
    final store = ModuleConfigPrefs(WebUiRoot.instance);
    SharedPreferencesStorePlatform.instance = SharedPreferencesWebUiStore(
      stock: SharedPreferencesStorePlatform.instance,
      prefs: store,
    );
    SharedPreferencesAsyncPlatform.instance = SharedPreferencesWebUiAsync(
      stock: SharedPreferencesAsyncPlatform.instance!,
      prefs: store,
    );
  }
}
