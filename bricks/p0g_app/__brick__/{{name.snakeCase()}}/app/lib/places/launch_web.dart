import 'package:flutter_webui_client/flutter_webui_client.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:{{name.snakeCase()}}_core/{{name.snakeCase()}}_core.dart';

/// Web: the process place exists on a WebUI host, through flutter-webui's
/// root channel. In a plain browser there is none.
ProcessPlace? openProcessPlace() {
  final host = WebUi.host;
  final moduleDir = host.moduleDir;
  if (!host.isWebUi || moduleDir == null) return null;
  return webUiProcessPlace(
    WebUi.connectRootChannel,
    moduleDir: moduleDir,
    app: '{{name.snakeCase()}}',
  );
}
