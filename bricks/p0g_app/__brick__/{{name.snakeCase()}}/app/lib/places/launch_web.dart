import 'package:squadron_process/squadron_process.dart';

import 'webui_launcher.dart';

/// Web: the process place exists only on WebUI, through flutter-webui's root
/// channel, once main() has connected it ([rootChannel]).
ProcessPlace? processPlaceFor(String service) {
  final channel = rootChannel;
  if (channel == null) return null;
  return webUiProcessPlace(channel, '{{name.snakeCase()}}', service);
}
