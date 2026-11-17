# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is https://github.com/p0g-stack/.github/blob/main/docs/flutter-bump.md.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| Squadron commit the patch series applies to | `third_party/squadron/PIN` (`commit`; upstream has no tag) | 7.4.5, `fd5becc` | squadron_process, with `third_party/squadron/patches` |
| Squadron version range | `pubspec.yaml` `squadron` | `>=7.4.5 <7.5.0` | squadron_process, same commit as PIN |
| Shared patch helper | `pubspec.yaml` `patched_source` `ref` | flutter_p0g `d3b6de0` | squadron_process, after a helper change lands in flutter_p0g |
| Dart SDK used by CI | `.github/workflows/test.yml` `sdk` | 3.13.7 (Flutter 3.47.9's Dart) | squadron_process when Flutter moves |

Consumers pin this repo by commit: bricks' p0g_app brick and demo (`ref:` in core/app/cli `pubspec.yaml`).
