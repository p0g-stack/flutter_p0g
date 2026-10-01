// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// path_provider on a WebUI host: the paths a module's root side uses,
/// shaped like `path_provider_linux` (state per app id, shared user
/// directories, a system temp dir). The page itself cannot open them; they
/// are for the app's root process and for root-channel commands.
///
/// | Method | Path | Linux equivalent |
/// |---|---|---|
/// | temporary | `/data/local/tmp` | `$TMPDIR` or `/tmp` |
/// | application support | `/data/adb/<id>` (created) | `~/.local/share/<app id>` |
/// | application cache | `/data/adb/<id>/cache` (created) | `~/.cache/<app id>` |
/// | documents | `/storage/emulated/0/Documents` | XDG documents |
/// | downloads | `/storage/emulated/0/Download` | XDG download |
///
/// State lives outside `/data/adb/modules/<id>` because a module update
/// replaces that directory. Library and external-storage paths are
/// unimplemented, as on Linux.
///
/// In a browser tab there are no paths: [stock] answers (the method channel,
/// which fails with `MissingPluginException` as stock web does).
final class PathProviderWebUiImpl extends PathProviderPlatform {
  PathProviderWebUiImpl({required this.stock, required this.root});

  final PathProviderPlatform stock;
  final WebUiRoot root;

  static const String temporaryPath = '/data/local/tmp';
  static const String sharedStorage = '/storage/emulated/0';

  String? get _stateDir {
    final id = root.moduleId;
    return id == null ? null : '/data/adb/$id';
  }

  final Map<String, Future<String>> _created = {};

  /// Creates [path] as root once (`mkdir -p`, mode 700).
  Future<String> _ensure(String path) => _created[path] ??= () async {
    final r = await root.run(['/system/bin/mkdir', '-p', '-m', '700', path]);
    if (!r.ok) {
      _created.remove(path);
      throw PlatformException(
        code: 'webui-mkdir-failed',
        message: 'mkdir $path: ${r.errorText.trim()}',
      );
    }
    return path;
  }();

  @override
  Future<String?> getTemporaryPath() async =>
      root.available ? temporaryPath : stock.getTemporaryPath();

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = _stateDir;
    if (!root.available || dir == null) {
      return stock.getApplicationSupportPath();
    }
    return _ensure(dir);
  }

  @override
  Future<String?> getApplicationCachePath() async {
    final dir = _stateDir;
    if (!root.available || dir == null) {
      return stock.getApplicationCachePath();
    }
    await _ensure(dir);
    return _ensure('$dir/cache');
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => root.available
      ? '$sharedStorage/Documents'
      : stock.getApplicationDocumentsPath();

  @override
  Future<String?> getDownloadsPath() async =>
      root.available ? '$sharedStorage/Download' : stock.getDownloadsPath();
}
