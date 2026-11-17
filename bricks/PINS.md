# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is https://github.com/p0g-stack/.github/blob/main/docs/flutter-bump.md.

All live in the p0g_app brick, `bricks/p0g_app/__brick__/{{name.snakeCase()}}/`; generated apps (demo) copy them.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| squadron_process | `core/`, `app/`, `cli/` `pubspec.yaml` `ref:` | `8f639eb8d2e200866ace17cca03c9d7c4705f5f9` | bricks, after squadron_process lands |
| flutter-webui (flutter_webui_client and friends) | `core/`, `app/`, `cli/` `pubspec.yaml` `ref:` | `72df180304562037fbc720153967fbb70a362eb1` | bricks; **must equal flutter_p0g's `kFlutterWebuiCommit`** |
| flutter_rust_bridge (Dart side) | `core/pubspec.yaml` `ref:` | `1e4df906` (`2.14.0-beta.2` Rust) | bricks; must equal flutter_p0g's `kFrbCommit` |
| p0g_lints (this repo) | `analysis_options.yaml` include `ref:` | `8e3d47f` | bricks, when p0g_lints changes |
| Flutter | `.github/workflows/ci.yaml` `flutter-version` | 3.47.9 | bricks when Flutter moves |
| patched_source | root `pubspec.yaml` dev dependency | `d3b6de00bd5e88910b9b42036a819b06159085f5` | frozen helper-package commit, shared with squadron_process |
| flutter_p0g (CI tool) | `.github/workflows/ci.yaml` `FLUTTER_P0G_REF` | `2612b4d73a4f643d49f30d0940917b15f4ae09a3` | bricks after the tool's qualified Flutter 3.47.9 / WebUI X v660 bump |

Consumers supply this repo's full published SHA as `BRICKS_REF` in CI and local regeneration commands; the generated checker never embeds its own ref.
