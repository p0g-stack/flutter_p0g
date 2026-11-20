// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// flutter_local_notifications for WebUI hosts (`docs/plugins.md`).
library;

import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_local_notifications_web/flutter_local_notifications_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'src/flutter_local_notifications_webui_impl.dart';

/// Registers the WebUI implementation of flutter_local_notifications' web
/// platform. It extends the endorsed web class, so the app-facing plugin
/// (which looks up `WebFlutterLocalNotificationsPlugin` on web) uses it
/// unchanged; when this package is a direct dependency Flutter registers it
/// instead of `flutter_local_notifications_web`.
abstract final class FlutterLocalNotificationsWebUi {
  static void registerWith(Registrar registrar) {
    FlutterLocalNotificationsPlatform.instance =
        FlutterLocalNotificationsWebUiImpl(
          stock: WebFlutterLocalNotificationsPlugin(),
          plane: AppPlane(WebUiRoot.instance),
        );
  }
}
