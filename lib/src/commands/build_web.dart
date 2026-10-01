import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/commands/build_web.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../frb/frb.dart';
import '../squadron.dart';
import '../webui/flutter_webui.dart' show P0gArtifacts;
import '../webui/workers.dart';

/// `flutter build web` for a p0g app in an ordinary browser tab: the stock
/// build, plus the two things it cannot make on its own.
///
/// - The app's Rust crate as frb wasm, single-threaded (`--no-threads`), so
///   any static host serves it without COOP/COEP headers.
/// - Squadron Web Workers, compiled to the `~/workers/...` paths their
///   activators load.
///
/// Nothing of WebUI: stock web SDK, stock bootstrap, stock defaults (CDN,
/// service worker), output in `build/web`. Every `build web` flag works and
/// means what it means there.
class BuildWebP0gCommand extends BuildWebCommand {
  BuildWebP0gCommand({required super.verboseHelp})
    : super(logger: globals.logger, fileSystem: globals.fs);

  @override
  String get description =>
      'Build a web application bundle, with the app\'s Rust wasm and Squadron Web Workers.';

  @override
  Future<FlutterCommandResult> runCommand() async {
    // Stock web SDK even when `precache --webui` built the patched one.
    P0gArtifacts.useStockWebSdk = true;
    final Directory app = project.directory;
    // squadron_process apps need its patched Squadron; set up on first use.
    await ensurePatchedSquadron(app);
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
    final workers = findWorkers(app, wasm: boolArg(FlutterOptions.kWebWasmFlag));
    await compileWorkers(workers, web, release: buildInfo.isRelease);
    globals.printStatus(
      'Built ${fs.path.relative(web.path)} '
      '(${workers.length} worker${workers.length == 1 ? '' : 's'}'
      '${usesFrb(app) ? ', Rust wasm in pkg/' : ''}).',
    );
    return result;
  }
}
