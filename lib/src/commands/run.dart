import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/commands/run.dart' as fl;
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/web/devfs_config.dart';
import 'package:flutter_tools/src/web/web_device.dart';
import 'package:meta/meta.dart';

import '../webui/module.dart';
import '../webui/dev_proxy.dart';
import '../squadron.dart';
import '../webui/flutter_webui.dart';
import '../webui/plugin.dart';
import '../webui/webui_packages.dart';
import '../adb.dart';
import 'run_aera.dart';

/// `flutter run` for WebUI: flutter_tools' `web-server` device (DDC, hot
/// reload and restart, the debug service) built against the patched web SDK
/// with the flutter_webui plugin, behind a dev proxy that adds CORS and
/// flutter-webui's bootstrap. The module's page loads the app from the proxy
/// through flutter-webui's `dev.html`: with a device on adb, `run` reverses
/// the port and swaps the installed module's `index.html` for that entry
/// until it exits.
class RunCommand extends fl.RunCommand {
  RunCommand({super.verboseHelp = false}) {
    argParser
      ..addSeparator('WebUI options')
      ..addOption(
        'dev-port',
        defaultsTo: '8800',
        help: 'Port of the dev server the module page loads the app from (device and host).',
      )
      ..addOption('serial', abbr: 's', help: 'adb serial (default: the only device, if any).')
      ..addSeparator('AERA options')
      ..addFlag(
        'aera',
        negatable: false,
        help:
            'Run the AERA plugin instead: build a debug .aerap, install it in AERA '
            'recovery (adb), start it and attach (hot reload, restart, DevTools).',
      )
      ..addOption('aerap', help: 'aera: install this .aerap instead of building one.')
      ..addFlag('ram', negatable: false, help: "aera: install into AERA's RAM store.")
      ..addFlag(
        'device-swap',
        defaultsTo: true,
        help:
            'With a device on adb: reverse the dev port and point the installed '
            "module's page at the dev server while running.",
      );
  }

  @override
  String get description =>
      'Run the app in a WebUI page with hot reload: the module page on the device '
      '(adb) or any browser loads it from a dev server on this machine.';

  String? _entrypoint;

  @override
  bool boolArg(String name, {bool global = false}) {
    // Managers can't rely on a CDN (and WebUI X's CSP blocks gstatic), as in
    // `build webui`.
    if (!global && name == FlutterOptions.kWebResourcesCdnFlag && !argResults!.wasParsed(name)) {
      return false;
    }
    return super.boolArg(name, global: global);
  }

  @override
  String get targetFile => _entrypoint ?? super.targetFile;

  int get _devPort => int.tryParse(stringArg('dev-port')!) ?? throwToolExit('Bad --dev-port.');

  /// flutter_tools' dev server, on a free loopback port behind the proxy.
  int? _upstreamPort;

  @override
  Future<FlutterCommandResult> verifyThenRunCommand(String? commandPath) async {
    if (boolArg('aera')) {
      final code = await runAera(
        app: project.directory,
        adb: Adb.find(stringArg('serial')),
        vmPort:
            // The stock option; AERA's engine needs a fixed port to forward.
            int.tryParse(stringArg('vm-service-port') ?? '8181') ??
            throwToolExit('Bad --vm-service-port.'),
        ram: boolArg('ram'),
        buildArgs: [if (stringArg('target') case final t?) '--target=$t'],
        aerap: stringArg('aerap') == null ? null : globals.fs.file(stringArg('aerap')),
      );
      if (code != 0) throwToolExit('flutter attach exited with $code.', exitCode: code);
      return FlutterCommandResult.success();
    }
    // The page is the device; flutter_tools serves it as `web-server`. Set
    // before anything (artifacts, validation) looks devices up.
    WebServerDevice.showWebServerDevice = true;
    globals.deviceManager!.specifiedDeviceId = 'web-server';
    return await super.verifyThenRunCommand(commandPath);
  }

  @override
  Future<WebDevServerConfig?> getWebDevServerConfig() async {
    final config = await super.getWebDevServerConfig();
    _upstreamPort ??= await _freePort();
    return config?.copyWith(host: '127.0.0.1', port: _upstreamPort);
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    await precacheFlutterWebui();
    await precacheWebuiPackages();
    await ensurePatchedSquadron(project.directory);
    _upstreamPort ??= await _freePort();
    final proxy = await WebUiDevProxy.start(
      port: _devPort,
      upstream: Uri.parse('http://127.0.0.1:$_upstreamPort/'),
      bootstrap: bootstrapDir(),
      flutterJs: flutterJsFile(),
      fonts: fallbackFontsDir(),
    );
    final page = _DevPage(project.directory, proxy.url);
    globals.printStatus('WebUI dev server: ${proxy.url} (open dev.html?dev=${proxy.url})');

    _DeviceSwap? swap;
    if (boolArg('device-swap')) swap = await _DeviceSwap.start(stringArg('serial'), page);
    globals.shutdownHooks.addShutdownHook(() async {
      await swap?.restore();
      await proxy.close();
    });

    try {
      return await withWebuiPlugin(project.directory, super.targetFile, (overlay) async {
        _entrypoint = overlay.entrypoint;
        try {
          return await super.runCommand();
        } finally {
          _entrypoint = null;
        }
      });
    } finally {
      await swap?.restore();
      await proxy.close();
    }
  }
}

Future<int> _freePort() async {
  final s = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

/// The module's dev entry: flutter-webui's `dev.html` pointed at the proxy.
class _DevPage {
  _DevPage(Directory app, this.devServer)
    : moduleId = _moduleId(app.childDirectory('webui').childFile('module.prop'));

  static String? _moduleId(File prop) =>
      prop.existsSync() ? readProp(prop.readAsStringSync(), 'id') : null;

  final String? moduleId;
  final Uri devServer;

  String html() => fillDevHtml(
    bootstrapDir().childFile('dev.html').readAsStringSync(),
    moduleId: moduleId ?? '',
    devServer: devServer,
  );
}

/// Points an installed module's page at the dev server over adb, and back.
class _DeviceSwap {
  _DeviceSwap(this._adb, this._webroot);

  final List<String> _adb;
  final String _webroot;
  bool _restored = false;

  static Future<_DeviceSwap?> start(String? serial, _DevPage page) async {
    final adbPath = globals.androidSdk?.adbPath ?? globals.os.which('adb')?.path;
    if (adbPath == null) {
      globals.printStatus('No adb: open the dev server from a browser or a WebUI page.');
      return null;
    }
    final adb = [
      adbPath,
      if (serial != null) ...['-s', serial],
    ];
    final state = await _run([...adb, 'get-state'], check: false);
    if (state == null || state.trim() != 'device') {
      globals.printStatus('No adb device: open the dev server from a browser or a WebUI page.');
      return null;
    }
    final id = page.moduleId;
    if (id == null) throwToolExit('No id in webui/module.prop. Run `flutter_p0g create .`.');
    final webroot = '/data/adb/modules/$id/webroot';
    final port = page.devServer.port;
    await _run([...adb, 'reverse', 'tcp:$port', 'tcp:$port']);
    final installed = await _run([
      ...adb,
      'shell',
      'su -c ${shellQuote('[ -d ${shellQuote(webroot)} ] && echo yes')}',
    ], check: false);
    if (installed?.trim() != 'yes') {
      globals.printStatus(
        'Module $id is not installed: run `flutter_p0g build webui` and `flutter_p0g install`, '
        'reboot, then run again. The dev server is reachable on the device at ${page.devServer}.',
      );
      return null;
    }
    final tmp = globals.fs.systemTempDirectory.createTempSync('p0g_dev');
    final local = tmp.childFile('index.html')..writeAsStringSync(page.html());
    const remote = '/data/local/tmp/flutter_p0g_dev.html';
    await _run([...adb, 'push', local.path, remote]);
    tmp.deleteSync(recursive: true);
    await _run([...adb, 'shell', 'su -c ${shellQuote(swapInScript(webroot, remote))}']);
    globals.printStatus("Module $id's page now loads from ${page.devServer}; reopen it.");
    return _DeviceSwap(adb, webroot);
  }

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    await _run([..._adb, 'shell', 'su -c ${shellQuote(swapOutScript(_webroot))}'], check: false);
  }

  static Future<String?> _run(List<String> cmd, {bool check = true}) async {
    final r = await globals.processUtils.run(cmd);
    if (r.exitCode != 0) {
      if (check) throwToolExit('${cmd.join(' ')} failed:\n${r.stderr}');
      return null;
    }
    return r.stdout;
  }
}

/// Keeps the release page as `index.release.html` (once, so a crashed run
/// never loses it) and puts the dev entry at `index.html`.
@visibleForTesting
String swapInScript(String webroot, String devHtml) {
  final w = shellQuote(webroot);
  return 'cd $w && { [ -f index.release.html ] || mv index.html index.release.html; } && '
      'cp ${shellQuote(devHtml)} index.html && chmod 0644 index.html && rm -f ${shellQuote(devHtml)}';
}

@visibleForTesting
String swapOutScript(String webroot) {
  final w = shellQuote(webroot);
  return 'cd $w && [ -f index.release.html ] && mv -f index.release.html index.html';
}
