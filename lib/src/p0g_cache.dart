import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_tools/src/base/common.dart';
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

/// Reads a kit archive from a local path or an https URL (GitHub release
/// assets use GITHUB_TOKEN when set, for private repos).
Future<List<int>> fetchBytes(String source) async {
  if (!source.startsWith('https://')) return globals.fs.file(source).readAsBytesSync();
  final client = io.HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(source));
    final token = globals.platform.environment['GITHUB_TOKEN'];
    if (token != null && source.startsWith('https://github.com/')) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    final response = await request.close();
    if (response.statusCode != 200) {
      throwToolExit('GET $source: HTTP ${response.statusCode}.');
    }
    return [for (final chunk in await response.toList()) ...chunk];
  } finally {
    client.close();
  }
}

/// The engine revision of the pinned Flutter.
String engineRevision() => globals.fs
    .file(globals.fs.path.join(Cache.flutterRoot!, 'bin', 'internal', 'engine.version'))
    .readAsStringSync()
    .trim();

/// Decodes a `.tar.gz`, dropping the `./` prefix `tar -C dir .` writes.
Archive decodeTarGz(List<int> bytes) {
  final archive = Archive();
  for (final f in TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes)).files) {
    if (!f.isFile) continue;
    final name = f.name.startsWith('./') ? f.name.substring(2) : f.name;
    archive.addFile(ArchiveFile(name, f.size, f.content)..mode = f.mode);
  }
  return archive;
}
