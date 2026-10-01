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

/// The app plane from the page: the module's own copy of webui-termux-api
/// (Termux:API repackaged, renamed per module to [appPlanePackage] and placed
/// by the module) called as root through the root channel.
///
/// A call runs `<moddir>/webui_app_plane/termux-api [--wait s] <Method> [extras]`, the
/// Dart port of termux-api from termux-api-package (`bin/webui_termux_api.dart`),
/// with the method's stdin and stdout.
final class AppPlane {
  AppPlane(this.root, {String? package})
    : package =
          package ??
          (root.moduleId == null
              ? termuxApiPackage
              : appPlanePackage(root.moduleId!));

  final WebUiRoot root;

  /// The app's package: the module's own ([appPlanePackage]) unless given.
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

  /// Where hand-off folders live: the app's cache dir, which Android may
  /// also reclaim.
  String get handoffRoot => '/data/data/$package/cache/handoff';

  Future<void>? _swept;
  int _handoffs = 0;

  /// A fresh hand-off folder for one call (`<handoffRoot>/<call id>`).
  /// Methods that read or write a `file` extra run as the app's uid, so their
  /// files go here, never in module storage. Every call gets its own folder,
  /// so a call never sees another call's file and two calls never wipe each
  /// other. The first hand-off of an [AppPlane] removes what earlier pages
  /// left behind.
  Future<AppHandoff> handoff() async {
    await (_swept ??= root
        .run(['/system/bin/rm', '-rf', handoffRoot])
        .then((_) {}, onError: (Object _) {}));
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${(_handoffs++).toRadixString(36)}';
    return AppHandoff._(this, '$handoffRoot/$id');
  }

  /// Calls [method] with am-style [extras] (`--es name value`, `--ez name
  /// true`, ...), sending [input] on its stdin. Returns its stdout. [wait]
  /// is how long the app may take to answer (the launcher's default, 10 s,
  /// when null); methods that wait on the user pass more.
  Future<RootResult> call(
    String method, {
    List<String> extras = const [],
    List<int>? input,
    Duration? wait,
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
      if (wait != null) ...['--wait', '${wait.inSeconds}'],
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

  /// Asks the media provider to index [paths] (files the app wrote to shared
  /// storage such as `Download` or `Documents`), so they show in Files and
  /// Gallery apps. Call it after the write; directories are not walked.
  ///
  /// A root `MEDIA_SCANNER_SCAN_FILE` broadcast per file, which MediaProvider
  /// handles (devicelab, Android 15); no app needed. It does not report
  /// whether the provider indexed a file.
  Future<void> scanMedia(List<String> paths) async {
    if (paths.isEmpty) return;
    if (!root.available) {
      throw const AppPlaneException(
        'unavailable',
        'a media scan needs a WebUI host with the root channel',
      );
    }
    for (final path in paths) {
      final r = await root.run([
        '/system/bin/am',
        'broadcast',
        '--user',
        'current',
        '-a',
        'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d',
        Uri.file(path).toString(),
      ]);
      if (!r.ok) {
        throw AppPlaneException(
          'failed',
          'media scan of $path exited ${r.exitCode}: ${r.errorText.trim()}',
        );
      }
    }
  }
}

/// One call's hand-off folder in the app's cache dir (from
/// [AppPlane.handoff]). Root writes files there for the app, or collects
/// what the app wrote, then [delete]s it.
final class AppHandoff {
  AppHandoff._(this._plane, this.dir);

  final AppPlane _plane;

  /// The folder: `/data/data/<package>/cache/handoff/<call id>`.
  final String dir;

  /// The path of [name] in [dir], made safe (no `/`, no leading `.`).
  String path(String name) {
    final safe = name.replaceAll(RegExp(r'[/\x00]'), '_');
    return '$dir/${safe.isEmpty || safe.startsWith('.') ? 'file$safe' : safe}';
  }

  /// The shell script that creates [dir] for the app and, given a file,
  /// writes stdin to it: owned by the app and labelled with its data dir's
  /// SELinux context (categories included).
  static const String _script =
      r'set -e; d=$1; f=$2; a=${d%/cache/handoff/*}; h=$a/cache/handoff; '
      r'mkdir -p "$d"; [ -z "$f" ] || cat > "$f"; '
      r'o=$(stat -c %u:%g "$a"); chown "$o" "$a/cache"; chown -R "$o" "$h"; '
      r'chmod 700 "$h" "$d"; [ -z "$f" ] || chmod 600 "$f"; '
      // restorecon drops the app's MLS categories (devicelab, Android 15):
      // copy the data dir's full context instead.
      r'c=$(stat -c %C "$a" 2>/dev/null || ls -dZ "$a" | cut -d" " -f1); '
      r'case "$c" in *:*) chcon "$c" "$a/cache"; chcon -R "$c" "$h" ;; esac';

  /// Creates [dir], empty and owned by the app, for a method that writes
  /// into it (DocumentOpen, CameraPhoto). Returns [dir].
  Future<String> create() async {
    final r = await _plane.root.sh(_script, args: [dir, '']);
    if (!r.ok) {
      throw AppPlaneException(
        'failed',
        'could not create $dir: ${r.errorText.trim()}',
      );
    }
    return dir;
  }

  /// Writes [bytes] to [name] in [dir], owned by the app and labelled with
  /// its data dir's SELinux context (categories included). Returns the path.
  Future<String> write(String name, List<int> bytes) async {
    final file = path(name);
    final r = await _plane.root.sh(_script, args: [dir, file], stdin: bytes);
    if (!r.ok) {
      throw AppPlaneException(
        'failed',
        'could not write $file: ${r.errorText.trim()}',
      );
    }
    return file;
  }

  /// Removes [dir] and everything in it.
  Future<void> delete() async {
    await _plane.root.run(['/system/bin/rm', '-rf', dir]);
  }
}
