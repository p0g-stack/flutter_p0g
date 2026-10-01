// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'root.dart';
import 'termux_api_names.dart';

/// A failed app-plane call.
final class AppPlaneException implements Exception {
  const AppPlaneException(this.code, this.message);

  /// `unavailable` (no root channel), `not-installed` (the app is missing or
  /// disabled), or `failed` (the call ran and failed).
  final String code;
  final String message;

  @override
  String toString() => 'AppPlaneException($code): $message';
}

/// The app plane from the page: webui-termux-api (Termux:API repackaged as
/// [termuxApiPackage], placed by the module) called as root through the root
/// channel.
///
/// A call runs `<moddir>/webui_app_plane/termux-api <Method> [extras]`, the
/// Dart port of termux-api from termux-api-package (`bin/webui_termux_api.dart`),
/// with the method's stdin and stdout.
final class AppPlane {
  AppPlane(this.root, {this.package = termuxApiPackage});

  final WebUiRoot root;

  /// The app's package.
  final String package;

  Future<bool>? _installed;

  /// Whether the app can be called: the root channel exists and
  /// `pm path <package>` finds the app. The first check also grants the app
  /// the `SYSTEM_ALERT_WINDOW` appop: methods that open an activity (Share's
  /// chooser, dialogs) run from a broadcast, and Android 10+ blocks those
  /// background activity starts without it (devicelab, Android 15).
  /// Checked once per [AppPlane].
  Future<bool> isAvailable() {
    if (!root.available) return Future.value(false);
    return _installed ??= () async {
      try {
        final found = await root.run(['/system/bin/pm', 'path', package]);
        if (!found.ok || !found.text.contains('package:')) return false;
        await root.run([
          '/system/bin/appops',
          'set',
          package,
          'SYSTEM_ALERT_WINDOW',
          'allow',
        ]);
        return true;
      } on Object {
        return false;
      }
    }();
  }

  /// The app's private directory for this module's files
  /// (`/data/data/<package>/files/<moduleId>`). Methods that read a `file`
  /// extra run as the app's uid, so files they read go here (written by
  /// [writeAppFile]), never in the module directory.
  String appFileDir() =>
      '/data/data/$package/files/${root.moduleId ?? 'webui'}';

  /// Writes [bytes] to [name] in [appFileDir], owned by the app and labelled
  /// with its data dir's SELinux context (categories included), after removing what earlier calls left there. Returns the path.
  Future<String> writeAppFile(String name, List<int> bytes) async {
    final safe = name.replaceAll(RegExp(r'[/\x00]'), '_');
    final dir = appFileDir();
    final path =
        '$dir/${safe.isEmpty || safe.startsWith('.') ? 'file$safe' : safe}';
    final r = await root.sh(
      r'set -e; d=$1; f=$2; a=${d%/files/*}; '
      r'rm -rf "$d"; mkdir -p "$d"; cat > "$f"; '
      r'o=$(stat -c %u:%g "$a"); chown "$o" "$a/files"; chown -R "$o" "$d"; '
      r'chmod 700 "$d"; chmod 600 "$f"; '
      // restorecon drops the app's MLS categories (devicelab, Android 15):
      // copy the data dir's full context instead.
      r'c=$(stat -c %C "$a" 2>/dev/null || ls -dZ "$a" | cut -d" " -f1); '
      r'case "$c" in *:*) chcon "$c" "$a/files"; chcon -R "$c" "$d" ;; esac',
      args: [dir, path],
      stdin: bytes,
    );
    if (!r.ok) {
      throw AppPlaneException(
        'failed',
        'could not write $path: ${r.errorText.trim()}',
      );
    }
    return path;
  }

  /// Calls [method] with am-style [extras] (`--es name value`, `--ez name
  /// true`, ...), sending [input] on its stdin. Returns its stdout.
  Future<RootResult> call(
    String method, {
    List<String> extras = const [],
    List<int>? input,
  }) async {
    if (!root.available) {
      throw const AppPlaneException(
        'unavailable',
        'the app plane needs a WebUI host with the root channel',
      );
    }
    if (!await isAvailable()) {
      throw AppPlaneException(
        'not-installed',
        '$package is not installed or is disabled; the module places it',
      );
    }
    final r = await root.run([
      '/system/bin/sh',
      '${root.moduleDir}/webui_app_plane/termux-api',
      '--package',
      package,
      method,
      ...extras,
    ], stdin: input);
    if (!r.ok) {
      throw AppPlaneException(
        'failed',
        '$method exited ${r.exitCode}: ${r.errorText.trim()}',
      );
    }
    return r;
  }
}
