import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import '../p0g_cache.dart';

/// A Squadron Web Worker entry point and where its activator loads it from.
class WorkerEntry {
  WorkerEntry(this.source, this.output);

  /// The generated `*.web.g.dart`.
  final File source;

  /// Path under the web root, e.g. `workers/demo_service.web.g.dart.js`.
  final String output;
}

final _workerUri = RegExp(r'''Squadron\.uri\(\s*['"]~/([^'"]+\.(js|wasm))['"]''');

/// The `~/...` worker URLs a generated `*.web.g.dart` loads, relative to the
/// page's base href.
@visibleForTesting
List<String> workerOutputs(String generatedSource) => [
  for (final m in _workerUri.allMatches(generatedSource)) m.group(1)!,
];

/// Squadron worker entry points in the app and, for a pub workspace, in its
/// sibling packages (the bricks `core/`).
List<WorkerEntry> findWorkers(Directory app, {required bool wasm}) {
  final roots = <Directory>[app];
  final parentPubspec = app.parent.childFile('pubspec.yaml');
  if (parentPubspec.existsSync() && parentPubspec.readAsStringSync().contains('workspace:')) {
    for (final dir in app.parent.listSync().whereType<Directory>()) {
      if (dir.path != app.path && dir.childFile('pubspec.yaml').existsSync()) roots.add(dir);
    }
  }
  final entries = <WorkerEntry>[];
  for (final root in roots) {
    final lib = root.childDirectory('lib');
    if (!lib.existsSync()) continue;
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.web.g.dart')) continue;
      for (final out in workerOutputs(f.readAsStringSync())) {
        if (out.endsWith('.wasm') && !wasm) continue;
        entries.add(WorkerEntry(f, out));
      }
    }
  }
  return entries;
}

/// Compiles each worker into [webRoot] at the path its activator expects,
/// as `dart compile js` (or `wasm`) would by hand.
Future<void> compileWorkers(
  List<WorkerEntry> workers,
  Directory webRoot, {
  required bool release,
}) async {
  for (final w in workers) {
    // Absolute: the compiler runs in the worker's source directory, so a
    // relative `--output` would land the worker beside its source.
    final out = webRoot.childFile(w.output).absolute..parent.createSync(recursive: true);
    final wasm = w.output.endsWith('.wasm');
    globals.printStatus('Compiling worker ${w.output}...');
    final r = await globals.processUtils.run([
      dartBinary(),
      'compile',
      if (wasm) 'wasm' else 'js',
      if (!wasm) ...[release ? '-O2' : '-O0', '--no-source-maps'],
      '-o',
      out.path,
      w.source.path,
    ], workingDirectory: w.source.parent.path);
    if (r.exitCode != 0) throwToolExit('Worker ${w.output} failed to compile:\n$r');
    for (final extra in ['${out.path}.deps', '${out.path}.map']) {
      final f = globals.fs.file(extra);
      if (f.existsSync()) f.deleteSync();
    }
  }
}
