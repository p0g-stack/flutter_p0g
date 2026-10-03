# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is /mnt/project-files/proposals/flutter-bump-checklist.md (project files).

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| flutter-webui (flutter_webui_client) | `packages/{webui_app_plane,clipboard_webui,file_selector_webui,dynamic_color_webui}/pubspec.yaml` `ref:` | `74d0575` | webui-packages; keep equal to flutter_p0g's `kFlutterWebuiCommit` |
| Flutter used by CI | `.github/workflows/ci.yaml` `flutter-version` | 3.47.5 | webui-packages when Flutter moves |

The webui-termux-api fork is owned here but released from p0g-stack/webui-termux-api; flutter_p0g pins that release by tag and sha256.
Consumers: flutter_p0g pins this repo by `kWebuiPackagesCommit`.
