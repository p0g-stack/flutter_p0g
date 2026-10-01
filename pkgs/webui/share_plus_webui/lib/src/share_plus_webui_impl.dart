// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// share_plus on a WebUI host.
///
/// Manager WebViews have no `navigator.share`, so stock web would fall back to
/// a `mailto:` link or a download. On a WebUI host with webui-termux-api the
/// share goes to the Android share sheet through its `Share` method
/// (webui-termux-api `apis/ShareAPI.java`):
///
/// - text or a URI: stdin, `--es action send`, `--es title <subject>`;
/// - one file: copied into the app's own files dir (the method opens it as
///   the app's uid), `--es file <path>`, `--es action send`, and
///   `--es content-type` when the XFile has one.
///
/// ShareAPI takes one file and no text with it; more than one file is a
/// [PlatformException]. It reports no outcome, so the result is
/// [ShareResult.unavailable], as on Linux.
///
/// Without the app (or in a browser tab) it is [stock], built with the WebUI
/// url_launcher so its `mailto:` fallback opens the mail app.
final class SharePlusWebUiImpl extends SharePlatform {
  SharePlusWebUiImpl({required this.stock, required this.plane});

  final SharePlatform stock;
  final AppPlane plane;

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (!await plane.isAvailable()) return stock.share(params);
    final files = params.files ?? const [];
    if (files.length > 1) {
      throw PlatformException(
        code: 'webui-share-multiple-files',
        message:
            'webui-termux-api Share takes one file (${files.length} given)',
      );
    }
    final subject = params.subject;
    final extras = [
      '--es',
      'action',
      'send',
      if (subject != null) ...['--es', 'title', subject],
    ];
    final RootResult r;
    try {
      if (files.isEmpty) {
        final text = params.text ?? params.uri?.toString() ?? '';
        r = await plane.call(
          'Share',
          extras: extras,
          input: text.isEmpty ? null : utf8.encode(text),
        );
      } else {
        final file = files.single;
        final names = params.fileNameOverrides;
        // An absolute path is a root path (file_selector_webui, the root
        // process); anything else (blob:, data:, a bare name) is page data.
        final rootPath = file.path.startsWith('/');
        var name = names != null && names.isNotEmpty ? names.first : file.name;
        if (name.isEmpty && rootPath) name = file.path.split('/').last;
        if (name.isEmpty) name = 'shared';
        // The target app reads the file after Share returns, so the
        // hand-off stays until a later page's sweep finds it old.
        final handoff = await plane.handoff();
        final path = rootPath
            ? await handoff.copyFrom(file.path, name)
            : await handoff.write(name, await file.readAsBytes());
        final type = file.mimeType;
        r = await plane.call(
          'Share',
          extras: [
            ...extras,
            '--es',
            'file',
            path,
            if (type != null) ...['--es', 'content-type', type],
          ],
        );
      }
    } on AppPlaneException catch (e) {
      throw PlatformException(code: 'webui-${e.code}', message: e.message);
    }
    // ShareAPI prints its errors to stdout and still exits normally.
    final out = r.text.trim();
    if (out.toLowerCase().startsWith('error')) {
      throw PlatformException(code: 'webui-share-failed', message: out);
    }
    return ShareResult.unavailable;
  }
}
