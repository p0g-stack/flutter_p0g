import 'dart:io';

import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';

/// Desktop: the CLI named by `P0G_CLI` (a `--dart-define` or the
/// environment), started with the caller's rights. An elevated helper uses
/// `ElevatedLauncher.forHost()` instead.
ProcessPlace? openProcessPlace() {
  const defined = String.fromEnvironment('P0G_CLI');
  final cli = defined.isNotEmpty ? defined : Platform.environment['P0G_CLI'];
  if (cli == null || cli.isEmpty) return null;
  final session = '${_privateDir().path}/place.json';
  return ProcessPlace(
    launcher: const IoProcessLauncher(),
    store: FileEndpointStore(session),
    command: ProcessCommand(
      cli,
      arguments: ['serve', '--session-file', session],
    ),
  );
}

/// The session file holds the token, so it lives where only this user can
/// read: `$XDG_RUNTIME_DIR` (0700) when there is one, else a fresh mkdtemp.
Directory _privateDir() {
  final runtime = Platform.environment['XDG_RUNTIME_DIR'];
  if (runtime != null && runtime.isNotEmpty) {
    return Directory('$runtime/{{name.snakeCase()}}')..createSync(recursive: true);
  }
  return Directory.systemTemp.createTempSync('{{name.snakeCase()}}');
}
