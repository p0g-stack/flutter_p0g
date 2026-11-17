# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is https://github.com/p0g-stack/.github/blob/main/docs/flutter-bump.md.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| flutter-webui (patched web SDK source, root channel) | `lib/src/webui/flutter_webui.dart` `kFlutterWebuiCommit` | `8951e5f` | flutter_p0g; **must equal bricks' p0g_app pin** |
| Patched web SDK (flutter-webui `web-sdk-release`) | `lib/src/webui/flutter_webui.dart` `kWebSdkRelease`, `kWebSdkSha256`, `kWebSdkTree`, `kWebSdkEngine` | `web-sdk-3.47.5-af7e796-93b29c6`, sha256 `c961ec08…63d7ae7`, web_ui tree `2b9eb41`, engine `af7e796` | flutter_p0g after flutter-webui cuts a release; precache downloads it only when the pinned flutter-webui's `web_ui/` tree and the installed engine match, else builds locally |
| webui-packages (`*_webui` plugins) | `lib/src/webui/webui_packages.dart` `kWebuiPackagesCommit` | `0e7bbcb` | flutter_p0g |
| webui-termux-api APK (app plane) | `lib/src/webui/app_plane.dart` `kAppPlaneTag`, `kAppPlaneSha256` | `webui-v0.53.0-webui.9`, sha256 `659cdd70…4949b` | flutter_p0g after a webui-termux-api release |
| flutter_rust_bridge + `patches/frb` | `lib/src/frb/frb.dart` `kFrbCommit` | `1e4df906b6d0e96aefbfa40dde5fa2833d417c1a`; Rust crate `2.14.0-beta.2` | flutter_p0g; must equal bricks' frb `ref:` and Rust dependency version |
| Android Dart SDK kit | `lib/src/artifact_pins.dart` `dartAndroidKitPins`, selected by exact Dart version/ABI | Dart 3.13.4 and 3.13.7, arm64-v8a + x86_64; immutable asset-ID URLs and SHA256 from downloaded release bytes | flutter_p0g: build uploads artifacts only, then `dart-android-kit-release` validates the run and publishes `dart-android-<Dart>-<producer-full-SHA>` without replacement |
| AERA runtime kit | `lib/src/artifact_pins.dart` `aeraKitPins`, selected by exact Flutter version/target/mode | Flutter 3.47.5, linux-arm64-debug + linux-x64-debug; immutable asset-ID URLs and SHA256 from downloaded release bytes | flutter-aera Kit publishes `kit-<Flutter>-<producer-full-SHA>` without replacement; explicit local/HTTPS kits require SHA256; installs are staged with a complete identity stamp |
| Flutter | `.github/workflows/ci.yml` `flutter-version`; the tool runs on the user's installed Flutter | 3.47.5 | flutter_p0g when Flutter moves |

Consumers: demo pins this repo by `FLUTTER_P0G_REF` in `.github/workflows/ci.yml`.
