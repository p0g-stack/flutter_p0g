import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';

import 'native.dart' show loadNative;

/// Native: the first library found, in this order.
///
/// 1. `P0G_NATIVE_LIB`, a full path.
/// 2. Beside the executable: `bin/<abi>/` on WebUI, where flutter_p0g packs
///    it with the CLI's snapshot and `dartaotruntime`; beside a
///    `dart compile exe` binary on a desktop.
/// 3. `lib/` beside the executable: a Flutter Linux bundle.
/// 4. `rust/target/{release,debug}/` in this workspace, found upward from
///    the working directory: `dart run`, `dart test`, `flutter test`.
/// 5. The bare name, for the OS loader (an Android app's `jniLibs`).
Future<ExternalLibrary?> openNativeLibrary(String stem) async {
  final name = Platform.isMacOS
      ? 'lib$stem.dylib'
      : Platform.isWindows
      ? '$stem.dll'
      : 'lib$stem.so';
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    ?Platform.environment['P0G_NATIVE_LIB'],
    '$exeDir/$name',
    '$exeDir/lib/$name',
    ..._workspaceBuilds(name),
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return ExternalLibrary.open(path);
  }
  return ExternalLibrary.open(name);
}

Iterable<String> _workspaceBuilds(String name) sync* {
  var dir = Directory.current.absolute;
  while (true) {
    for (final profile in ['release', 'debug']) {
      yield '${dir.path}/rust/target/$profile/$name';
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return;
    dir = parent;
  }
}

/// Native: loading the library is cheap, so the fact is the real load.
Future<bool> nativeShipped(String stem) => loadNative();
