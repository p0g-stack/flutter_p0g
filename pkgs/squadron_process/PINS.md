# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is /mnt/project-files/proposals/flutter-bump-checklist.md (project files).

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| Squadron release the patch series applies to | `third_party/squadron/PIN` (`tag`, `commit`) | v7.4.4, `4ab7f15` | squadron_process, with `third_party/squadron/patches` |
| Squadron version range | `pubspec.yaml` `squadron` | `>=7.4.4 <7.5.0` | squadron_process, same commit as PIN |
| Dart SDK used by CI | `.github/workflows/test.yml` `sdk` | 3.13.4 (Flutter 3.47.5's Dart) | squadron_process when Flutter moves |

Consumers pin this repo by commit: bricks' p0g_app brick and demo (`ref:` in core/app/cli `pubspec.yaml`).
