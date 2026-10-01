// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

/// Page side, shared by the `*_webui` plugins: [WebUiRoot] (the host and root
/// commands) and [AppPlane] (webui-termux-api through the root channel).
/// Plain Dart, no `dart:io`.
library;

export 'src/app_plane.dart';

export 'package:flutter_webui_client/flutter_webui_client.dart'
    show RootChannelException;

export 'src/root.dart';
export 'src/termux_api_names.dart';
