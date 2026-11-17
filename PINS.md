# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is https://github.com/p0g-stack/.github/blob/main/docs/flutter-bump.md.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| flutter-webui (patched web SDK source, root channel) | `lib/src/webui/flutter_webui.dart` `kFlutterWebuiCommit` | `374766e3913972aedca2e0a7778d88b5d398459a` | flutter_p0g; **must equal bricks' p0g_app pin** |
| Patched web SDK (flutter-webui `web-sdk-release`) | `lib/src/webui/flutter_webui.dart` `kWebSdkRelease`, `kWebSdkSha256`, `kWebSdkTree`, `kWebSdkEngine` | `web-sdk-3.47.9-89c39ed-374766e`, sha256 `d85ae597…daa653`, web_ui tree `95c08d3`, engine `89c39ed` | flutter_p0g after flutter-webui cuts a release; precache downloads it only when the pinned flutter-webui's `web_ui/` tree and the installed engine match, else builds locally |
| webui-packages (`*_webui` plugins) | `lib/src/webui/webui_packages.dart` `kWebuiPackagesCommit` | `9f860cbc23d80b7f0c17ad0df0d589677c0605e2` | flutter_p0g |
| webui-termux-api APK (app plane) | `lib/src/webui/app_plane.dart` `kAppPlaneTag`, `kAppPlaneSha256` | `webui-v0.53.0-webui.9`, sha256 `659cdd70…4949b` | flutter_p0g after a webui-termux-api release |
| flutter_rust_bridge + `patches/frb` | `lib/src/frb/frb.dart` `kFrbCommit` | `1e4df906b6d0e96aefbfa40dde5fa2833d417c1a`; Rust crate `2.14.0-beta.2` | flutter_p0g; must equal bricks' frb `ref:` and Rust dependency version |
| Android Dart SDK kit | `lib/src/artifact_pins.dart` `dartAndroidKitPins`, selected by exact Dart version/ABI | Dart 3.13.4 and 3.13.7, arm64-v8a + x86_64; immutable asset-ID URLs and SHA256 from downloaded release bytes | flutter_p0g: build uploads artifacts only, then `dart-android-kit-release` validates the run and publishes `dart-android-<Dart>-<producer-full-SHA>` without replacement |
| AERA runtime kit | `lib/src/artifact_pins.dart` `aeraKitPins`, selected by exact Flutter version/target/mode | Flutter 3.47.9, linux-arm64-debug + linux-x64-debug; `kit-3.47.9-0c28b4e291849f008d7ee3fd063e2670d0f9116b`, qualified by [Kit run 44043686997](https://github.com/p0g-stack/flutter-aera/actions/runs/44043686997); historical 3.47.5 entries retained | flutter-aera Kit publishes `kit-<Flutter>-<producer-full-SHA>` without replacement; explicit local/HTTPS kits require SHA256; installs are staged with a complete identity stamp |
| Flutter | `.github/workflows/ci.yml` `flutter-version`; the tool runs on the user's installed Flutter | 3.47.9 | flutter_p0g when Flutter moves |

Consumers: demo pins this repo by `FLUTTER_P0G_REF` in `.github/workflows/ci.yml`.
