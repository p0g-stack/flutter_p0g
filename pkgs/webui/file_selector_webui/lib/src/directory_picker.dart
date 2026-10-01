// Copyright 2026 The p0g-stack authors.
// SPDX-License-Identifier: LGPL-3.0-or-later WITH LGPL-3.0-linking-exception

import 'package:webui_app_plane/webui_app_plane.dart';

/// One entry of a root listing.
final class DirEntry {
  const DirEntry(this.name, {required this.isDirectory});

  final String name;
  final bool isDirectory;

  @override
  bool operator ==(Object other) =>
      other is DirEntry &&
      other.name == name &&
      other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(name, isDirectory);

  @override
  String toString() => isDirectory ? '$name/' : name;
}

/// A listing that failed (no such directory, no permission).
final class ListingException implements Exception {
  const ListingException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'ListingException($path): $message';
}

/// Lists directories as root through the root channel.
final class RootDirectoryLister {
  RootDirectoryLister(this.root);

  final WebUiRoot root;

  /// Entries of [dir], directories first, then by name ignoring case.
  /// Symlinks to directories count as directories (toybox `ls -L`).
  Future<List<DirEntry>> list(String dir) async {
    final r = await root.run(['/system/bin/ls', '-1ApL', '--', dir]);
    // ls exits 1 for a dangling symlink and still lists the rest.
    if (!r.ok && r.text.isEmpty) {
      throw ListingException(dir, r.errorText.trim());
    }
    final entries = [
      for (final line in r.text.split('\n'))
        if (line.isNotEmpty)
          line.endsWith('/')
              ? DirEntry(line.substring(0, line.length - 1), isDirectory: true)
              : DirEntry(line, isDirectory: false),
    ];
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}

/// What the picker is for.
enum PickMode {
  /// Choose an existing directory.
  directory,

  /// Choose a directory and type a file name.
  save,
}

/// One picker request.
final class PickRequest {
  const PickRequest({
    required this.mode,
    required this.initialDirectory,
    this.suggestedName,
    this.confirmButtonText,
  });

  final PickMode mode;
  final String initialDirectory;
  final String? suggestedName;
  final String? confirmButtonText;
}

/// Shows a picker over [PickerState] and returns the chosen path, or null
/// when the user cancels.
abstract interface class DirectoryDialog {
  Future<String?> show(PickerState state);
}

/// Where the picker is and what it shows. The dialog only renders this and
/// forwards user actions; the logic lives here so it is testable without a
/// DOM.
final class PickerState {
  PickerState(this.request, this.lister)
    : _directory = _clean(request.initialDirectory);

  /// Where to start when no initial directory is given: the primary user's
  /// shared storage.
  static const String defaultDirectory = '/storage/emulated/0';

  final PickRequest request;
  final RootDirectoryLister lister;

  String _directory;
  List<DirEntry> _entries = const [];
  String? _error;

  /// The directory shown.
  String get directory => _directory;

  /// Its entries (after [open]).
  List<DirEntry> get entries => _entries;

  /// Why the last [open] failed, or null.
  String? get error => _error;

  bool get canGoUp => _directory != '/';

  /// Lists [path]; on failure stays where it was and sets [error].
  Future<void> open(String path) async {
    final target = _clean(path);
    try {
      _entries = await lister.list(target);
      _directory = target;
      _error = null;
    } on ListingException catch (e) {
      _error = e.message.isEmpty ? 'Cannot open $target' : e.message;
    }
  }

  /// Lists [directory]; if it cannot be read, walks up until something can.
  Future<void> start() async {
    var path = _directory;
    await open(path);
    while (_error != null && path != '/') {
      path = parentOf(path);
      await open(path);
    }
  }

  Future<void> enter(String name) => open(joinPath(_directory, name));

  Future<void> up() => open(parentOf(_directory));

  /// The path to return for [fileName] (save mode) or the directory itself.
  String result([String? fileName]) {
    if (request.mode == PickMode.directory) return _directory;
    final name = fileName?.trim() ?? '';
    return name.isEmpty ? '' : joinPath(_directory, name);
  }

  /// Whether [fileName] is usable in save mode: non-empty, no `/`, not `.`
  /// or `..`.
  static bool validName(String fileName) {
    final name = fileName.trim();
    return name.isNotEmpty &&
        !name.contains('/') &&
        name != '.' &&
        name != '..';
  }
}

String _clean(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return '/${parts.join('/')}';
}

/// [name] inside [dir].
String joinPath(String dir, String name) => _clean('$dir/$name');

/// The parent of [path] (`/` for `/`).
String parentOf(String path) => _clean('$path/..');
