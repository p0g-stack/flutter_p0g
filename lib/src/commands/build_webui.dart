import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/commands/build_web.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../frb/frb.dart';
import '../webui/cli_exe.dart';
import '../webui/dart_android.dart';
import '../webui/module.dart';

/// `flutter build web` with WebUI defaults, then the module zip.
///
/// Every `build web` flag still works; only the defaults differ: CanvasKit
/// and fonts are bundled (no manager may reach a CDN) and no service worker
/// is registered (no manager runs one).
class BuildWebUiCommand extends BuildWebCommand {
  BuildWebUiCommand({required super.verboseHelp})
    : super(logger: globals.logger, fileSystem: globals.fs) {
    argParser.addSeparator('WebUI options');
    argParser.addOption(
      'cli-format',
      allowed: ['aot', 'exe'],
      defaultsTo: 'aot',
      help:
          'How cli/ ships: an AOT snapshot plus the Android Dart runtime kit, '
          'or a single executable (for a Dart SDK that can target Android).',
    );
  }

  @override
  String get name => 'webui';

  @override
  String get description => 'Build a KernelSU-style WebUI module (.zip) from the app.';

  @override
  bool boolArg(String name, {bool global = false}) {
    if (!global && name == FlutterOptions.kWebResourcesCdnFlag && !argResults!.wasParsed(name)) {
      return false;
    }
    return super.boolArg(name, global: global);
  }

  @override
  String? stringArg(String name, {bool global = false}) {
    if (!global && name == 'pwa-strategy' && !argResults!.wasParsed(name)) return 'none';
    return super.stringArg(name, global: global);
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    final Directory app = project.directory;
    final Directory webui = app.childDirectory('webui');
    if (!webui.childFile('module.prop').existsSync()) {
      throwToolExit('No webui/module.prop. Run `flutter_p0g create .` first.');
    }
    final BuildInfo buildInfo = await getBuildInfo();

    if (usesFrb(app)) {
      globals.printStatus('flutter_rust_bridge.yaml found: building wasm without threads.');
      await frbBuildWeb(app, release: buildInfo.isRelease);
    }

    final result = await super.runCommand();

    final fs = globals.fs;
    final Directory web = fs.directory(
      stringArg('output') ?? fs.path.join(app.path, getWebBuildDirectory()),
    );
    final Directory out = app.childDirectory('build').childDirectory('webui');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);

    final extra = <String, List<int>>{};
    final cli = CliPackage.find(app);
    if (cli != null) {
      globals.printStatus('Compiling ${cli.dir.path} for the device...');
      if (stringArg('cli-format') == 'exe') {
        final exe = out.childDirectory('bin').childFile(cli.name);
        await compileCli(cli, exe);
        extra['bin/${cli.name}'] = exe.readAsBytesSync();
      } else {
        final kit = DartAndroidKit.forVersion(sdkDartVersion());
        extra.addAll(await compileCliAot(cli, kit, out.childDirectory('cli')));
      }
      final rust = cli.dir.parent.childDirectory('rust');
      if (rust.childFile('Cargo.toml').existsSync()) {
        for (final so in await buildRustForCli(rust, out.childDirectory('jniLibs'))) {
          extra['bin/$kAbi/${so.basename}'] = so.readAsBytesSync();
        }
      }
    }

    final buildName = buildInfo.buildName ?? project.manifest.buildName ?? '1.0.0';
    final buildNumber = buildInfo.buildNumber ?? project.manifest.buildNumber ?? '1';
    final files = assembleModule(
      webBuild: _readTree(web),
      webuiFolder: _readTree(webui),
      extra: extra,
      buildName: buildName,
      buildNumber: buildNumber,
      wasm: boolArg(FlutterOptions.kWebWasmFlag),
    );
    final prop = utf8.decode(files.firstWhere((f) => f.path == 'module.prop').bytes);
    final id = readProp(prop, 'id') ?? project.manifest.appName;
    final File zip = out.childFile('$id-v$buildName.zip')..writeAsBytesSync(zipModule(files));
    final size = (zip.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    globals.printStatus('Built ${fs.path.relative(zip.path)} ($size MB, ${files.length} files).');
    return result;
  }

  Map<String, List<int>> _readTree(Directory root) {
    final files = <String, List<int>>{};
    if (!root.existsSync()) return files;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = globals.fs.path.relative(entity.path, from: root.path).replaceAll(r'\', '/');
      files[rel] = entity.readAsBytesSync();
    }
    return files;
  }
}
