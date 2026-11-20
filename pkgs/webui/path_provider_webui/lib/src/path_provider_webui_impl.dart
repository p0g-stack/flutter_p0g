// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

/// path_provider on a WebUI host: the paths a module's root side uses. The
/// page itself cannot open them; they are for the app's root process and for
/// root-channel commands. Lifetimes follow the module (flutter-webui keeps
/// them: a fresh install starts empty, temp is cleared on the first start of
/// each boot), as Android's are tied to the app.
///
/// | Method | Path | Lifetime |
/// |---|---|---|
/// | temporary | `/data/adb/<id>/tmp` (created) | the creator deletes; cleared each boot |
/// | application support | `/data/adb/<id>` (created) | until uninstall |
/// | application documents | `/data/adb/<id>/documents` (created) | until uninstall, private as on Android |
/// | application cache | `/data/adb/<id>/cache` (created) | may be cleared |
/// | downloads | `/storage/emulated/0/Download` | the user's |
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

  /// [_stateDir]/[name], created with its parent.
  Future<String?> _sub(
    String name,
    Future<String?> Function() stockPath,
  ) async {
    final dir = _stateDir;
    if (!root.available || dir == null) return stockPath();
    await _ensure(dir);
    return _ensure('$dir/$name');
  }

  @override
  Future<String?> getTemporaryPath() => _sub('tmp', stock.getTemporaryPath);

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = _stateDir;
    if (!root.available || dir == null) {
      return stock.getApplicationSupportPath();
    }
    return _ensure(dir);
  }

  @override
  Future<String?> getApplicationCachePath() =>
      _sub('cache', stock.getApplicationCachePath);

  @override
  Future<String?> getApplicationDocumentsPath() =>
      _sub('documents', stock.getApplicationDocumentsPath);

  @override
  Future<String?> getDownloadsPath() async =>
      root.available ? '$sharedStorage/Download' : stock.getDownloadsPath();
}
