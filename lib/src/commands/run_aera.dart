import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import '../adb.dart';
import 'install.dart';

/// AERA's per-plugin data directory, as Host API 3 patch 0005 picks it:
/// internal storage when `/sdcard/AERA` is a directory, else RAM.
@visibleForTesting
String aeraDataDirScript(String id) =>
    'if [ -d /sdcard/AERA ]; then echo /sdcard/AERA/plugin-data/$id; '
    'else echo /tmp/aera/plugin-data/$id; fi';

/// Prepares [dataDir] for a debug start (flutter-aera `docs/debugging.md`):
/// the VM service on [port], no stale URL file.
@visibleForTesting
String aeraDebugSetupScript(String dataDir, int port) {
  final d = shellQuote(dataDir);
  return 'mkdir -p $d && echo --vm-service-port=$port > $d/engine-switches && '
      'rm -f $d/vm-service-url';
}

/// `run` for AERA: build a debug `.aerap`, install it in AERA recovery over
/// adb, start it with the VM service on [vmPort], forward that port and hand
/// over to the stock `flutter attach` (hot reload, restart, DevTools), as
/// flutter-aera's `docs/debugging.md` describes.
Future<int> runAera({
  required Directory app,
  required Adb adb,
  required int vmPort,
  required bool ram,
  required List<String> buildArgs,
  File? aerap,
}) async {
  await requireAeraRecovery(adb);
  aerap ??= await _buildDebugAerap(app, buildArgs);
  final package = await installAeraPackage(adb, aerap, ram: ram);

  final dataDir = (await adb.run(['shell', aeraDataDirScript(package.id)]))!.trim();
  await adb.run(['shell', aeraDebugSetupScript(dataDir, vmPort)]);
  await adb.run(['forward', 'tcp:$vmPort', 'tcp:$vmPort']);
  try {
    await openAeraPlugin(adb, package.id);
    final url = await _vmServiceUrl(adb, dataDir);
    globals.printStatus('${package.id}: VM service at $url. Attaching...');
    final attach = await io.Process.start(
      globals.fs.path.join(Cache.flutterRoot!, 'bin', 'flutter'),
      ['attach', '--debug-url', url, '-d', 'flutter-tester'],
      workingDirectory: app.path,
      mode: io.ProcessStartMode.inheritStdio,
    );
    return await attach.exitCode;
  } finally {
    await adb.run(['forward', '--remove', 'tcp:$vmPort'], check: false);
  }
}

Future<File> _buildDebugAerap(Directory app, List<String> buildArgs) async {
  // The same tool, as its own process: `build aera` is a full flutter_tools
  // command with its own pub and artifact steps.
  final script = io.Platform.script.toFilePath();
  final code = await globals.processUtils.stream([
    io.Platform.resolvedExecutable,
    if (io.Platform.packageConfig case final config?)
      '--packages=${Uri.parse(config).toFilePath()}',
    script,
    'build',
    'aera',
    '--debug',
    ...buildArgs,
  ], workingDirectory: app.path);
  if (code != 0) throwToolExit('build aera failed (exit $code).');
  final out = app.childDirectory('build').childDirectory('aera');
  final built = out.existsSync()
      ? out.listSync().whereType<File>().where((f) => f.path.endsWith('.aerap')).toList()
      : <File>[];
  if (built.length != 1) throwToolExit('Expected one .aerap in ${out.path}.');
  return built.single;
}

/// Waits for the engine to write its VM service URL; the log on failure.
Future<String> _vmServiceUrl(Adb adb, String dataDir) async {
  final file = shellQuote('$dataDir/vm-service-url');
  for (var i = 0; i < 60; i++) {
    final url = (await adb.run(['shell', 'cat $file 2>/dev/null'], check: false))?.trim() ?? '';
    if (url.startsWith('http')) return url;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final log = await adb.run([
    'shell',
    'tail -n 40 ${shellQuote('$dataDir/aera-flutter.log')}',
  ], check: false);
  throwToolExit(
    'The plugin wrote no VM service URL in 30 s. Is the .aerap a debug build '
    'with a debug kit?\n${log ?? ''}',
  );
}
