# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is /mnt/project-files/proposals/flutter-bump-checklist.md (project files).

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| flutter-webui (patched web SDK source, root channel) | `lib/src/webui/flutter_webui.dart` `kFlutterWebuiCommit` | `a455782` | flutter_p0g; **must equal bricks' p0g_app pin** |
| Patched web SDK (flutter-webui `web-sdk-release`) | `lib/src/webui/flutter_webui.dart` `kWebSdkRelease`, `kWebSdkSha256`, `kWebSdkTree`, `kWebSdkEngine` | `web-sdk-3.47.5-af7e796-93b29c6`, sha256 `c961ec08…63d7ae7`, web_ui tree `2b9eb41`, engine `af7e796` | flutter_p0g after flutter-webui cuts a release; precache downloads it only when the pinned flutter-webui's `web_ui/` tree and the installed engine match, else builds locally |
| webui-packages (`*_webui` plugins) | `lib/src/webui/webui_packages.dart` `kWebuiPackagesCommit` | `0e7bbcb` | flutter_p0g |
| webui-termux-api APK (app plane) | `lib/src/webui/app_plane.dart` `kAppPlaneTag`, `kAppPlaneSha256` | `webui-v0.53.0-webui.9`, sha256 `659cdd70…4949b` | flutter_p0g after a webui-termux-api release |
| flutter_rust_bridge + `patches/frb` | `lib/src/frb/frb.dart` `kFrbCommit` | `848e438` | flutter_p0g; must equal bricks' frb `ref:` |
| Android Dart SDK kit | `lib/src/webui/dart_android.dart` `defaultKitUrl`: release `dart-android-<Dart version>` of this repo, Dart version read from the installed Flutter | dart-android-3.13.4 | flutter_p0g (`dart-android-kit` then `dart-android-kit-release` workflows). **Not hash-pinned**: sha256 only checked when passed to precache |
| AERA runtime kit | `lib/src/aera/kit.dart`: flutter-aera release `kit-<Flutter version>` | kit-3.47.5 | flutter-aera's Kit workflow. **Not hash-pinned** (`--aera-kit-sha256` optional) and that release is re-uploaded with `--clobber` |
| Flutter | `.github/workflows/ci.yml` `flutter-version`; the tool runs on the user's installed Flutter | 3.47.5 | flutter_p0g when Flutter moves |

Consumers: demo pins this repo by `FLUTTER_P0G_REF` in `.github/workflows/ci.yml`.
