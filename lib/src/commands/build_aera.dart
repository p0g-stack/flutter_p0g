import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/build_bundle.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../aera/aerap.dart';
import '../aera/kit.dart';
import '../templates.dart';

/// `flutter build bundle` for linux-arm64, plus AOT `libapp.so` for profile
/// and release, packed with flutter-aera's runtime kit into a `.aerap`
/// (flutter-aera `spec/aerap.md`). Debug builds carry `kernel_blob.bin` for a
/// debug (JIT) engine, like flutter-pi's.
class BuildAeraCommand extends BuildBundleCommand {
  BuildAeraCommand({super.verboseHelp}) : super(logger: globals.logger) {
    argParser.addSeparator('AERA options');
    argParser.addOption(
      'payload-url',
      defaultsTo: 'https://localhost/runtime.xz',
      help: 'Where runtime.xz will be published (any https URL for local installs).',
    );
  }

  @override
  String get name => 'aera';

  @override
  String get description => 'Build an AERA plugin (.aerap) from the app.';

  @override
  String? stringArg(String name, {bool global = false}) {
    if (!global && !argResults!.wasParsed(name)) {
      if (name == 'target-platform') return 'linux-arm64';
      if (name == 'asset-dir') {
        return globals.fs.path.join('build', 'aera', 'flutter_assets');
      }
    }
    return super.stringArg(name, global: global);
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    final Directory app = project.directory;
    final File appManifest = app.childDirectory('aera').childFile('plugin.json');
    if (!appManifest.existsSync()) {
      throwToolExit('No aera/plugin.json. Run `flutter_p0g create .` first.');
    }
    final BuildInfo buildInfo = await getBuildInfo();
    final target = stringArg('target-platform')!;
    final mode = buildInfo.mode.cliName;
    final kit = AeraKit.forTarget(target, mode);
    if (!kit.isInstalled) {
      throwToolExit(
        'No AERA runtime kit for $target-$mode. '
        'Run `flutter_p0g precache --aera-kit=<path or url>` with a flutter-aera kit.',
      );
    }

    final result = await super.runCommand();

    final fs = globals.fs;
    final out = app.childDirectory('build').childDirectory('aera');
    final assets = fs.directory(stringArg('asset-dir')).absolute;
    final members = <RuntimeMember>[];
    for (final f in _files(kit.payload)) {
      members.add(
        RuntimeMember(
          _rel(f, kit.payload),
          f.readAsBytesSync(),
          executable: f.statSync().mode & 0x49 != 0,
        ),
      );
    }
    for (final f in _files(assets)) {
      if (f.basename == '.last_build_id') continue;
      members.add(
        RuntimeMember('usr/share/flutter/flutter_assets/${_rel(f, assets)}', f.readAsBytesSync()),
      );
    }
    if (!buildInfo.isDebug) {
      final libapp = await _compileAot(kit, buildInfo, out.childDirectory('aot'), target);
      members.add(RuntimeMember('usr/lib/libapp.so', libapp.readAsBytesSync()));
    }

    final stream = runtimeStream(members);
    final rawFile = out.childFile('runtime')..writeAsBytesSync(stream);
    final xzFile = out.childFile('runtime.xz');
    if (xzFile.existsSync()) xzFile.deleteSync();
    final xz = await globals.processUtils.run([
      'xz',
      '--format=xz',
      '--check=crc32',
      '--arm64',
      '--lzma2=preset=6',
      '--keep',
      '--force',
      rawFile.path,
    ]);
    if (xz.exitCode != 0) throwToolExit('xz failed (needs XZ Utils 5.4+ for --arm64):\n$xz');
    rawFile.deleteSync();

    final buildName = buildInfo.buildName ?? project.manifest.buildName ?? '1.0.0';
    final buildNumber = buildInfo.buildNumber ?? project.manifest.buildNumber ?? '1';
    final appFields = jsonDecode(
      expandBuildVars(
        appManifest.readAsStringSync(),
        buildName: buildName,
        buildNumber: buildNumber,
      ),
    ) as Map<String, Object?>;
    final Map<String, Object?> manifest;
    try {
      manifest = pluginManifest(
        app: appFields,
        stream: stream,
        xz: xzFile.readAsBytesSync(),
        memberCount: members.length,
        payloadUrl: stringArg('payload-url')!,
      );
    } on FormatException catch (e) {
      throwToolExit(e.message);
    }
    final json = encodeManifest(manifest);
    out.childFile('plugin.json').writeAsStringSync(json);
    final aerap = out.childFile('${manifest['id']}-${manifest['version']}.aerap')
      ..writeAsBytesSync(aerapZip(json, xzFile.readAsBytesSync()));
    final size = (aerap.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    globals.printStatus(
      'Built ${fs.path.relative(aerap.path)} ($size MB, ${members.length} members).',
    );
    return result;
  }

  /// Kernel with the SDK's frontend server (flutter target, AOT), then the
  /// kit's gen_snapshot, which matches the kit's engine.
  Future<File> _compileAot(AeraKit kit, BuildInfo buildInfo, Directory work, String target) async {
    if (!kit.genSnapshot.existsSync()) throwToolExit('The kit lacks host/gen_snapshot.');
    final fs = globals.fs;
    final root = Cache.flutterRoot!;
    final sdk = fs.path.join(root, 'bin', 'cache', 'dart-sdk');
    final product = buildInfo.isRelease;
    final patched = fs.path.join(
      root,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'common',
      product ? 'flutter_patched_sdk_product' : 'flutter_patched_sdk',
    );
    work.createSync(recursive: true);
    final dill = work.childFile('app.dill');
    final libapp = work.childFile('libapp.so');
    Future<void> run(List<String> cmd) async {
      final r = await globals.processUtils.run(cmd, workingDirectory: project.directory.path);
      if (r.exitCode != 0) throwToolExit('${fs.path.basename(cmd.first)} failed:\n$r');
    }

    await run([
      fs.path.join(sdk, 'bin', 'dartaotruntime'),
      fs.path.join(sdk, 'bin', 'snapshots', 'frontend_server_aot.dart.snapshot'),
      '--sdk-root',
      '$patched/',
      '--target=flutter',
      '--aot',
      '--tfa',
      '--no-print-incremental-dependencies',
      if (product) '-Ddart.vm.product=true' else '-Ddart.vm.profile=true',
      for (final d in buildInfo.dartDefines) '-D$d',
      '--packages',
      buildInfo.packageConfigPath,
      '--output-dill',
      dill.path,
      fs.path.absolute(targetFile),
    ]);
    await run([
      kit.genSnapshot.path,
      '--deterministic',
      '--snapshot_kind=app-aot-elf',
      '--elf=${libapp.path}',
      if (product) '--strip',
      dill.path,
    ]);
    return libapp;
  }

  Iterable<File> _files(Directory root) => root.existsSync()
      ? root.listSync(recursive: true, followLinks: false).whereType<File>()
      : const <File>[];

  String _rel(File f, Directory root) =>
      globals.fs.path.relative(f.path, from: root.path).replaceAll(r'\', '/');
}
