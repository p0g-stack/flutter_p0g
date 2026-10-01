import 'dart:isolate';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

/// Where flutter_p0g keeps what `precache` fetches or builds: next to
/// Flutter's own cache, because everything in it is tied to the pinned
/// Flutter release.
Directory p0gCacheDir() =>
    globals.fs.directory(globals.fs.path.join(Cache.flutterRoot!, 'bin', 'cache', 'flutter_p0g'));

/// This package's root (for `patches/`), wherever it was activated from.
Future<Directory> toolPackageRoot() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_p0g/'));
  if (lib == null) throw StateError('cannot locate package:flutter_p0g');
  return globals.fs.directory(lib.toFilePath()).parent;
}

/// The SDK's `dart`, so the tool never picks another one off PATH.
String dartBinary() => globals.fs.path.join(
  Cache.flutterRoot!,
  'bin',
  globals.platform.isWindows ? 'dart.bat' : 'dart',
);
