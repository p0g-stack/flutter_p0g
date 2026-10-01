import 'dart:io';

import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';

/// Desktop: the CLI named by `P0G_CLI` (a `--dart-define` or the
/// environment), started with `dart:io`. Elevation (pkexec and the like)
/// is a different launcher, later.
ProcessPlace? processPlaceFor(String service) {
  const defined = String.fromEnvironment('P0G_CLI');
  final cli = defined.isNotEmpty ? defined : Platform.environment['P0G_CLI'];
  if (cli == null || cli.isEmpty) return null;
  final session =
      '${Directory.systemTemp.path}/{{name.snakeCase()}}.$service.place.json';
  return ProcessPlace(
    launcher: const IoProcessLauncher(),
    store: FileEndpointStore(session),
    command: ProcessCommand(
      cli,
      arguments: ['serve', service, '--session-file', session],
    ),
  );
}
