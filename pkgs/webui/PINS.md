# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is https://github.com/p0g-stack/.github/blob/main/docs/flutter-bump.md.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| flutter-webui (flutter_webui_client) | `packages/{webui_app_plane,clipboard_webui,file_selector_webui,dynamic_color_webui}/pubspec.yaml` `ref:` | `72df180` (WebUI X v660, root WifiEnable; compatible 3.47.9 branch, unchanged web SDK release `web-sdk-3.47.9-89c39ed-374766e`) | webui-packages; keep equal to flutter_p0g's `kFlutterWebuiCommit` |
| Flutter used by CI | `.github/workflows/ci.yaml` `flutter-version`; packages' `environment: flutter:` lower bound | 3.47.9 | webui-packages when Flutter moves |

The webui-termux-api fork is owned here but released from p0g-stack/webui-termux-api; flutter_p0g pins that release by tag and sha256.
Consumers: flutter_p0g pins this repo by `kWebuiPackagesCommit`.
