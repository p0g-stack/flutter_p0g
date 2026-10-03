# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is /mnt/project-files/proposals/flutter-bump-checklist.md (project files).

All live in the p0g_app brick, `bricks/p0g_app/__brick__/{{name.snakeCase()}}/`; generated apps (demo) copy them.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| squadron_process | `core/`, `app/`, `cli/` `pubspec.yaml` `ref:` | `28c37ce` | bricks, after squadron_process lands |
| flutter-webui (flutter_webui_client and friends) | `core/`, `app/`, `cli/` `pubspec.yaml` `ref:` | `a455782` | bricks; **must equal flutter_p0g's `kFlutterWebuiCommit`** |
| flutter_rust_bridge (Dart side) | `core/pubspec.yaml` `ref:` | `848e438` | bricks; must equal flutter_p0g's `kFrbCommit` |
| p0g_lints (this repo) | `analysis_options.yaml` include `ref:` | `8e3d47f` | bricks, when p0g_lints changes |
| Flutter | `.github/workflows/ci.yaml` `flutter-version` | 3.47.5 | bricks when Flutter moves |

Consumers: demo pins this repo by `BRICKS_REF` in `tool/regen.sh`.
