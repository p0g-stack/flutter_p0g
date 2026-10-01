import 'package:squadron_process/squadron_process.dart';

import 'webui_launcher.dart';

/// Web: the process place exists on a WebUI host, once [webUiRoot] is set
/// (see there). In a plain browser there is none.
ProcessPlace? openProcessPlace() {
  final root = webUiRoot;
  if (root == null) return null;
  return webUiProcessPlace(root, app: '{{name.snakeCase()}}');
}
