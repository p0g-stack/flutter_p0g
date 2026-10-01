import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/flutter_manifest.dart';
import 'package:flutter_tools/src/project.dart';

/// flutter_tools' project factory (uncached, as the stock tool runs it),
/// with a way to change one project's manifest while a build runs: WebUI
/// builds name the `*_webui` packages as the app's dependencies, which
/// flutter_tools reads from the manifest (`Plugin.isDirectDependency`).
class P0gProjectFactory extends FlutterProjectFactory {
  P0gProjectFactory({required super.logger, required super.fileSystem});

  final _manifests = <String, FlutterManifest Function(FlutterManifest)>{};

  /// Applies [change] to the manifest of the project in [directory] until
  /// the returned function is called.
  void Function() overrideManifest(
    Directory directory,
    FlutterManifest Function(FlutterManifest) change,
  ) {
    final key = directory.absolute.path;
    _manifests[key] = change;
    return () => _manifests.remove(key);
  }

  @override
  FlutterProject fromDirectory(Directory directory) {
    // ignore: invalid_use_of_visible_for_testing_member
    final project = projects.remove(directory.path) ?? super.fromDirectory(directory);
    // ignore: invalid_use_of_visible_for_testing_member
    projects.remove(directory.path);
    final change = _manifests[directory.absolute.path];
    if (change == null) return project;
    // ignore: invalid_use_of_visible_for_testing_member
    return FlutterProject(project.directory, change(project.manifest), project.example.manifest);
  }
}
