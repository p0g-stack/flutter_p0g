import 'dart:io' as io;
import 'dart:isolate';

import 'package:flutter_p0g_tool/src/artifact_lock.dart';
import 'package:flutter_p0g_tool/src/p0g_repository.dart';

/// The repository root on the real disk.
Future<io.Directory> realRepository() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_p0g_tool/'));
  return io.Directory.fromUri(lib!.resolve('../../../'));
}

/// The committed `artifacts.lock.json`.
Future<String> committedLockText() async =>
    io.File('${(await realRepository()).path}$kArtifactLockFile').readAsStringSync();

/// Copies the committed lock to where the tool reads it on the context's
/// file system (an in-memory one in tests).
Future<ArtifactLock> installCommittedLock() async {
  final text = await committedLockText();
  (await p0gRepository()).childFile(kArtifactLockFile)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  return ArtifactLock.parse(text);
}
