// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// file_selector for WebUI hosts (`docs/plugins.md`).
library;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:file_selector_web/file_selector_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/file_selector_webui_impl.dart';
import 'src/web/dom_directory_dialog.dart';

/// Registers the WebUI implementation of [FileSelectorPlatform].
///
/// When this package is a direct dependency of the app, Flutter registers it
/// instead of `file_selector_web` (only one web implementation per plugin is
/// registered), so it builds the stock one itself and hands it everything a
/// browser can do.
abstract final class FileSelectorWebUi {
  static void registerWith(Registrar registrar) {
    FileSelectorPlatform.instance = FileSelectorWebUiImpl(
      stock: FileSelectorWeb(),
      root: WebUiRoot.instance,
      dialog: const DomDirectoryDialog(),
    );
  }
}
