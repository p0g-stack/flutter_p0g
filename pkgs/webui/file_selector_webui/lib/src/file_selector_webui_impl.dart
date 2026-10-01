// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:webui_app_plane/webui_app_plane.dart';

import 'directory_picker.dart';

/// file_selector on a WebUI host.
///
/// - Opening files is the stock web route: every manager answers the
///   WebView's file chooser (`onShowFileChooser`), so [stock] handles it.
/// - Directories and save locations are real paths, which a browser cannot
///   give; on a WebUI host they come from a root listing shown by [dialog].
/// - In a browser tab (no root channel) everything is [stock].
final class FileSelectorWebUiImpl extends FileSelectorPlatform {
  FileSelectorWebUiImpl({
    required this.stock,
    required this.root,
    required this.dialog,
  });

  /// The stock web implementation (`FileSelectorWeb`).
  final FileSelectorPlatform stock;
  final WebUiRoot root;
  final DirectoryDialog dialog;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) => stock.openFile(
    acceptedTypeGroups: acceptedTypeGroups,
    initialDirectory: initialDirectory,
    confirmButtonText: confirmButtonText,
  );

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) => stock.openFiles(
    acceptedTypeGroups: acceptedTypeGroups,
    initialDirectory: initialDirectory,
    confirmButtonText: confirmButtonText,
  );

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
