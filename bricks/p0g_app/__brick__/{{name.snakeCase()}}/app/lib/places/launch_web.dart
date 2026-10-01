import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// Web: the process place exists on a WebUI host, through flutter-webui's
/// root channel. In a plain browser there is none.
///
/// This runs before the first frame, so nothing the host's bridge throws may
/// escape it: a host that fails detection gets no process place, and the app
/// still starts.
ProcessPlace? openProcessPlace() {
  final WebUiHost host;
  try {
    host = WebUi.host;
  } on Object catch (e) {
    Logger('places').warning('WebUI host detection failed; no process place', e);
    return null;
  }
  final moduleDir = host.moduleDir;
  if (!host.isWebUi || moduleDir == null) return null;
  return webUiProcessPlace(
    WebUi.connectRootChannel,
    moduleDir: moduleDir,
    app: '{{name.snakeCase()}}',
  );
}
