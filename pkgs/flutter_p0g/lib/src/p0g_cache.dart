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

/// Reads a local archive or HTTPS URL, including immutable GitHub asset IDs.
Future<List<int>> fetchBytes(String source) async {
  if (!source.startsWith('https://')) return globals.fs.file(source).readAsBytesSync();
  final client = io.HttpClient();
  try {
    var uri = Uri.parse(source);
    final token =
        globals.platform.environment['GITHUB_TOKEN'] ?? globals.platform.environment['GH_TOKEN'];
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https') throwToolExit('Refusing non-HTTPS redirect: $uri.');
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      if (uri.host == 'api.github.com') {
        request.headers.set('Accept', 'application/octet-stream');
        if (token != null && token.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $token');
        }
      }
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(io.HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) throwToolExit('GET $uri: redirect without Location.');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        throwToolExit('GET $uri: HTTP ${response.statusCode}.');
      }
      return [for (final chunk in await response.toList()) ...chunk];
    }
    throwToolExit('GET $source: too many redirects.');
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
Archive decodeTarGz(List<int> bytes) => decodeTar(GZipDecoder().decodeBytes(bytes));

/// Decodes a tar, dropping `./` prefixes and directory entries.
Archive decodeTar(List<int> tar) {
  final archive = Archive();
  for (final f in TarDecoder().decodeBytes(tar).files) {
    if (!f.isFile) continue;
    final name = f.name.startsWith('./') ? f.name.substring(2) : f.name;
    archive.addFile(ArchiveFile(name, f.size, f.content)..mode = f.mode);
  }
  return archive;
}
