import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/commands/build_web.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../frb/frb.dart';
import '../squadron.dart';
import '../webui/cli_exe.dart';
import '../webui/dart_android.dart';
import '../webui/flutter_webui.dart';
import '../webui/module.dart';
import '../webui/app_plane.dart';
import '../webui/plugin.dart';
import '../webui/webui_packages.dart';
import '../webui/workers.dart';

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
    argParser.addMultiOption(
      'abi',
      allowed: kDartArchForAbi.keys,
      defaultsTo: const [kDefaultAbi],
      help:
          'The ABIs whose programs (root channel, app plane, cli/, rust/) the module '
          'ships. Phones are arm64-v8a; add x86_64 for an x86_64 emulator.',
    );
    argParser.addFlag(
      'device-rust',
      defaultsTo: true,
      help:
          "Build rust/ for the device beside cli/ (cargo-ndk and the Android NDK). "
          'Without it the root process runs without the crate.',
    );
    argParser.addOption(
      'device-rust-libs',
      valueHelp: 'dir',
      help:
          'rust/ already built for the device: <dir>/<abi>/*.so (cargo-ndk -o layout), '
          'used in place of building it here.',
    );
    argParser.addFlag(
      'update-json',
      defaultsTo: true,
      help:
          "Set module.prop's updateJson and write update.json and changelog.md beside "
          "the zip, for the manager's update button. Publish all three with each release.",
    );
    argParser.addOption(
      'update-url',
      valueHelp: 'url',
      help:
          'Where releases publish the zip, update.json and changelog.md (a directory '
          "URL). Default: the updateJson already in webui/module.prop, else the latest "
          "release of the pubspec's GitHub repository.",
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

  /// The generated entrypoint that registers the flutter_webui plugin,
  /// while the web build runs.
  String? _webuiEntrypoint;

  @override
  String get targetFile => _webuiEntrypoint ?? super.targetFile;

  @override
  Future<FlutterCommandResult> runCommand() async {
    final Directory app = project.directory;
    final Directory webui = app.childDirectory('webui');
    if (!webui.childFile('module.prop').existsSync()) {
      throwToolExit('No webui/module.prop. Run `flutter_p0g create .` first.');
    }
    // squadron_process apps need its patched Squadron; set up on first use.
    await ensurePatchedSquadron(app);
    final BuildInfo buildInfo = await getBuildInfo();

    if (usesFrb(app)) {
      globals.printStatus('flutter_rust_bridge.yaml found: building wasm without threads.');
      await frbBuildWeb(app, release: buildInfo.isRelease);
    }

    // flutter-webui's bootstrap and patched web SDK (fetched and built on
    // first use, like flutter's own artifacts).
    await precacheFlutterWebui();
    await precacheWebuiPackages();

    // The flutter_webui web plugin (engine handlers), added for this build
    // only: apps depend on flutter_webui_client alone.
    var packages = <String>{};
    final result = await withWebuiPlugin(app, super.targetFile, (overlay) async {
      _webuiEntrypoint = overlay.entrypoint;
      packages = overlay.packages;
      try {
        return await super.runCommand();
      } finally {
        _webuiEntrypoint = null;
      }
    });

    final fs = globals.fs;
    final Directory web = fs.directory(
      stringArg('output') ?? fs.path.join(app.path, getWebBuildDirectory()),
    );
    final moduleProp = utf8.decode(webui.childFile('module.prop').readAsBytesSync());
    applyBootstrap(
      web,
      moduleId: readProp(moduleProp, 'id') ?? project.manifest.appName,
      title: readProp(moduleProp, 'name') ?? project.manifest.appName,
    );

    final workers = findWorkers(app, wasm: boolArg(FlutterOptions.kWebWasmFlag));
    await compileWorkers(workers, web, release: buildInfo.isRelease);

    final Directory out = app.childDirectory('build').childDirectory('webui');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);

    final extra = <String, List<int>>{};
    // web_ui's fallback fonts: the bootstrap points the engine at `fonts/`,
    // and a manager WebView has no system fonts.
    final fonts = fallbackFontsDir();
    for (final f in fonts.listSync(recursive: true).whereType<File>()) {
      extra['webroot/fonts/${fs.path.relative(f.path, from: fonts.path).replaceAll(r'\', '/')}'] = f
          .readAsBytesSync();
    }
    // flutter-webui's root channel, which the page starts through the
    // manager's bridge and which starts the app's root process.
    final installed = DartAndroidKit.installed(sdkDartVersion());
    final kits = {
      for (final abi in stringsArg('abi'))
        abi:
            installed[abi] ??
            throwToolExit(
              'The root channel needs the Dart Android kit for $abi. '
              'Run `flutter_p0g precache --dart-android --dart-android-abi=$abi`.',
            ),
    };
    globals.printStatus('Compiling the root channel for ${kits.keys.join(', ')}...');
    extra.addAll(await rootChannelFiles(kits, out.childDirectory('flutter_webui')));
    AppPlaneApp? appPlane;
    if (packages.contains(kAppPlanePackage)) {
      globals.printStatus('Adding the app plane (webui-termux-api $kAppPlaneTag)...');
      final moduleId = readProp(moduleProp, 'id') ?? project.manifest.appName;
      extra.addAll(
        await appPlaneFiles(
          kits,
          out.childDirectory('webui_app_plane'),
          moduleId: moduleId,
          title: readProp(moduleProp, 'name') ?? project.manifest.appName,
          key: appPlaneSigningKey(app),
        ),
      );
      appPlane = (package: appPlanePackageName(moduleId), versionCode: appPlaneVersionCode());
      globals.printStatus('App plane app: ${appPlane.package} ${appPlane.versionCode}.');
    }

    final cli = CliPackage.find(app);
    var abis = <String, DartAndroidKit>{};
    if (cli != null) {
      globals.printStatus('Compiling ${cli.dir.path} for the device...');
      if (stringArg('cli-format') == 'exe') {
        final exe = out.childDirectory('bin').childFile(cli.name);
        await compileCli(cli, exe);
        extra['bin/${cli.name}'] = exe.readAsBytesSync();
      } else {
        abis = kits;
        extra.addAll(await compileCliAot(cli, abis, out.childDirectory('cli')));
      }
      // cli/ and rust/ are one unit per ABI: the frb library sits beside
      // that ABI's snapshot and runtime. Rust never ships as its own binary.
      final rust = cli.dir.parent.childDirectory('rust');
      final prebuilt = stringArg('device-rust-libs');
      final targetAbis = abis.isEmpty ? const [kDefaultAbi] : abis.keys.toList();
      if (rust.childFile('Cargo.toml').existsSync() && !boolArg('device-rust')) {
        globals.printWarning('--no-device-rust: the root process ships without rust/.');
      } else if (rust.childFile('Cargo.toml').existsSync() || prebuilt != null) {
        final libs = prebuilt != null
            ? prebuiltRustLibs(fs.directory(prebuilt), targetAbis)
            : await buildRustForCli(rust, out.childDirectory('jniLibs'), targetAbis);
        libs.forEach((abi, files) {
          for (final so in files) {
            extra['bin/$abi/${so.basename}'] = so.readAsBytesSync();
          }
        });
      }
    }

    final buildName = buildInfo.buildName ?? project.manifest.buildName ?? '1.0.0';
    final buildNumber = buildInfo.buildNumber ?? project.manifest.buildNumber ?? '1';
    final webuiTree = _readTree(webui);
    final secrets = [...webuiTree.keys.where(isSigningSecret)];
    if (secrets.isNotEmpty) {
      globals.printWarning(
        'Left out of the module: ${secrets.map((p) => 'webui/$p').join(', ')}. Signing keys '
        'and key.properties never ship; keep them in android/ (android/key.properties).',
      );
    }
    final files = assembleModule(
      webBuild: _readTree(web),
      webuiFolder: webuiTree,
      extra: extra,
      buildName: buildName,
      buildNumber: buildNumber,
      wasm: boolArg(FlutterOptions.kWebWasmFlag),
      appPlane: appPlane,
    );
    final propIndex = files.indexWhere((f) => f.path == 'module.prop');
    var prop = utf8.decode(files[propIndex].bytes);
    final id = readProp(prop, 'id') ?? project.manifest.appName;
    final zipName = '$id-v$buildName.zip';
    final base = boolArg('update-json') ? _updateBase(prop) : null;
    if (base != null) {
      prop = withUpdateJson(prop, '$base$kUpdateJsonName');
      files[propIndex] = ModuleFile('module.prop', utf8.encode(prop));
    }
    final File zip = out.childFile(zipName)..writeAsBytesSync(zipModule(files));
    final size = (zip.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    globals.printStatus('Built ${fs.path.relative(zip.path)} ($size MB, ${files.length} files).');
    if (base != null) {
      out
          .childFile(kUpdateJsonName)
          .writeAsStringSync(
            updateJsonFor(
              base: base,
              version: readProp(prop, 'version') ?? 'v$buildName',
              versionCode: readProp(prop, 'versionCode') ?? buildNumber,
              zipName: zipName,
            ),
          );
      final changelog = [
        app.childFile('CHANGELOG.md'),
        app.parent.childFile('CHANGELOG.md'),
      ].where((f) => f.existsSync()).firstOrNull;
      out
          .childFile(kChangelogName)
          .writeAsStringSync(changelog?.readAsStringSync() ?? '# v$buildName\n');
      globals.printStatus(
        'Wrote $kUpdateJsonName and $kChangelogName beside it; publish them with the zip '
        'at $base.',
      );
    }
    return result;
  }

  /// The directory URL releases publish to, ending in `/`; null (with a
  /// note) when there is none.
  String? _updateBase(String moduleProp) {
    String dir(String url) => url.endsWith('/') ? url : '$url/';
    final given = stringArg('update-url');
    if (given != null) return dir(given);
    final existing = readProp(moduleProp, 'updateJson');
    if (existing != null && existing.isNotEmpty) {
      return existing.substring(0, existing.lastIndexOf('/') + 1);
    }
    final fromRepo = githubReleaseBase(_repository());
    if (fromRepo == null) {
      globals.printStatus(
        'No updateJson: pass --update-url, or set `repository:` (GitHub) in pubspec.yaml.',
      );
    }
    return fromRepo;
  }

  String? _repository() {
    for (final dir in [project.directory, project.directory.parent]) {
      final pubspec = dir.childFile('pubspec.yaml');
      if (!pubspec.existsSync()) continue;
      final m = RegExp(
        r'^repository:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync());
      if (m != null) return m[1]!.replaceAll(RegExp('''^['"]|['"]\$'''), '');
    }
    return null;
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
