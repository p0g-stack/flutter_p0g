// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'directory_picker.dart';

/// file_selector on a WebUI host.
///
/// - Opening files goes through the module's app when it is there: Android's
///   document picker (the app's `DocumentOpen`) copies the picked files into
///   a hand-off folder, root moves them to the module's temp dir
///   (`/data/adb/<id>/tmp/<call>`), and the [XFile]s carry those root paths,
///   name, type and size. No bytes cross the WebView: hand the path to the
///   app's root process. Without the app, the WebView's file chooser
///   (`onShowFileChooser`, [stock]) answers.
/// - Directories and save locations are real paths, which a browser cannot
///   give; on a WebUI host they come from a root listing shown by [dialog].
/// - In a browser tab (no root channel) everything is [stock].
final class FileSelectorWebUiImpl extends FileSelectorPlatform {
  FileSelectorWebUiImpl({
    required this.stock,
    required this.root,
    required this.dialog,
    AppPlane? plane,
  }) : plane = plane ?? AppPlane(root);

  /// The stock web implementation (`FileSelectorWeb`).
  final FileSelectorPlatform stock;
  final WebUiRoot root;
  final DirectoryDialog dialog;

  /// The module's app, for opening files.
  final AppPlane plane;

  /// How long the document picker may stay open.
  static const Duration pickWait = Duration(minutes: 30);

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (!await _useApp()) {
      return stock.openFile(
        acceptedTypeGroups: acceptedTypeGroups,
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
    }
    final files = await _openThroughApp(acceptedTypeGroups, multiple: false);
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (!await _useApp()) {
      return stock.openFiles(
        acceptedTypeGroups: acceptedTypeGroups,
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
    }
    return _openThroughApp(acceptedTypeGroups, multiple: true);
  }

  Future<bool> _useApp() async =>
      root.available && root.moduleId != null && await plane.isAvailable();

  /// The MIME types to offer: every group's, or none (any file) when a group
  /// filters only by extension, which Android's picker cannot.
  static List<String> mimeTypes(List<XTypeGroup>? groups) {
    if (groups == null || groups.isEmpty) return const [];
    final types = <String>{};
    for (final g in groups) {
      final m = g.mimeTypes;
      if (m == null || m.isEmpty) return const [];
      types.addAll(m);
    }
    return types.toList();
  }

  Future<List<XFile>> _openThroughApp(
    List<XTypeGroup>? groups, {
    required bool multiple,
  }) async {
    final handoff = await plane.handoff();
    try {
      final List<Object?> picked;
      try {
        await handoff.create();
        final mime = mimeTypes(groups);
        final r = await plane.call(
          'DocumentOpen',
          extras: [
            '--es',
            'dir',
            handoff.dir,
            if (mime.isNotEmpty) ...['--esa', 'mime', mime.join(',')],
            if (multiple) ...['--ez', 'multiple', 'true'],
          ],
          wait: pickWait,
        );
        final text = r.text.trim();
        final Object? answer;
        try {
          answer = jsonDecode(text);
        } on FormatException {
          throw PlatformException(
            code: 'webui-open-failed',
            message: text.isEmpty ? 'DocumentOpen gave no answer' : text,
          );
        }
        if (answer is! List) {
          throw PlatformException(
            code: 'webui-open-failed',
            message: answer is Map ? '${answer['error']}' : text,
          );
        }
        picked = answer;
      } on AppPlaneException catch (e) {
        throw PlatformException(code: 'webui-${e.code}', message: e.message);
      }
      if (picked.isEmpty) return const [];
      // Move the copies out of the app's hand-off folder into the module's
      // temp dir, owned by root.
      final call = handoff.dir.substring(handoff.dir.lastIndexOf('/') + 1);
      final target = '/data/adb/${root.moduleId}/tmp/open-$call';
      final moved = await root.sh(
        r'set -e; s=$1; t=$2; mkdir -p "$t"; chmod 700 "$t"; '
        r'for f in "$s"/* "$s"/.[!.]*; do [ -e "$f" ] && mv "$f" "$t"/; done; '
        r'chown -R 0:0 "$t"',
        args: [handoff.dir, target],
      );
      if (!moved.ok) {
        throw PlatformException(
          code: 'webui-open-failed',
          message: 'could not move the picked files: ${moved.errorText.trim()}',
        );
      }
      return [
        for (final item in picked.whereType<Map<Object?, Object?>>())
          XFile(
            '$target/${'${item['path']}'.split('/').last}',
            name: '${item['name']}',
            mimeType: item['mime'] as String?,
            length: (item['size'] as num?)?.toInt(),
          ),
      ];
    } finally {
      await handoff.delete();
    }
  }

  @override
  Future<String?> getSavePath({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    String? confirmButtonText,
  }) async {
    if (!root.available) {
      // ignore: deprecated_member_use
      return stock.getSavePath(
        acceptedTypeGroups: acceptedTypeGroups,
        initialDirectory: initialDirectory,
        suggestedName: suggestedName,
        confirmButtonText: confirmButtonText,
      );
    }
    final path = await _pick(
      PickRequest(
        mode: PickMode.save,
        initialDirectory: initialDirectory ?? PickerState.defaultDirectory,
        suggestedName: suggestedName,
        confirmButtonText: confirmButtonText,
      ),
    );
    return path == null || path.isEmpty ? null : path;
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    if (!root.available) {
      return stock.getSaveLocation(
        acceptedTypeGroups: acceptedTypeGroups,
        options: options,
      );
    }
    // ignore: deprecated_member_use_from_same_package
    final path = await getSavePath(
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: options.initialDirectory,
      suggestedName: options.suggestedName,
      confirmButtonText: options.confirmButtonText,
    );
    return path == null ? null : FileSaveLocation(path);
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    if (!root.available) {
      // ignore: deprecated_member_use
      return stock.getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
    }
    return _pick(
      PickRequest(
        mode: PickMode.directory,
        initialDirectory: initialDirectory ?? PickerState.defaultDirectory,
        confirmButtonText: confirmButtonText,
      ),
    );
  }

  @override
  Future<String?> getDirectoryPathWithOptions(FileDialogOptions options) =>
      // ignore: deprecated_member_use_from_same_package
      getDirectoryPath(
        initialDirectory: options.initialDirectory,
        confirmButtonText: options.confirmButtonText,
      );

  /// One directory at a time, as on Linux with `canSelectMultiple` off; the
  /// picker has no multi-select.
  @override
  Future<List<String>> getDirectoryPaths({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (!root.available) {
      // ignore: deprecated_member_use
      return stock.getDirectoryPaths(
        initialDirectory: initialDirectory,
        confirmButtonText: confirmButtonText,
      );
    }
    // ignore: deprecated_member_use_from_same_package
    final path = await getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
    return path == null ? const [] : [path];
  }

  @override
  Future<List<String>> getDirectoryPathsWithOptions(
    FileDialogOptions options,
  ) =>
      // ignore: deprecated_member_use_from_same_package
      getDirectoryPaths(
        initialDirectory: options.initialDirectory,
        confirmButtonText: options.confirmButtonText,
      );

  Future<String?> _pick(PickRequest request) async {
    final state = PickerState(request, RootDirectoryLister(root));
    try {
      await state.start();
    } on RootChannelException catch (e) {
      throw PlatformException(
        code: 'webui-root-unavailable',
        message: 'The root channel is not reachable: ${e.message}',
      );
    }
    return dialog.show(state);
  }
}
