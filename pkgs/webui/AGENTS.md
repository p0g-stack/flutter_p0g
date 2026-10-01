# webui-packages: working agreements

Self-contained; no external base file.

- Pattern first. Before writing a package, read the stock plugin's web and
  Linux implementations and match their behaviour and errors.
- Implement the plugin's platform interface; never ask an app to call
  something WebUI-specific.
- If the stock web implementation already works in the WebView, ship nothing.
- Host behaviour comes from `flutter_webui` detection, never a manager's name
  or version.
- Shell and Termux:API calls go through `flutter_webui`'s root channel and
  `webui_app_plane`. Keep the Termux:API contract as is; cite the
  `webui-termux-api` source (`TermuxApiReceiver.java`, `apis/*API.java`)
  for each method used.
- Anything the plugin changes globally (orientation, brightness, wakelock) is
  restored on exit.
- Host claims come from devicelab runs, with the device and manager named.
  Tests are unit tests against `flutter-webui` fakes.
