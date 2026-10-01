# flutter_p0g

The tool that takes a stock Flutter app to the p0g targets: **WebUI** (a
KernelSU-style module whose page runs in the root manager's WebView) and
**AERA** (a recovery plugin). Modeled on
[flutterpi_tool](https://pub.dev/packages/flutterpi_tool): a Dart package that
imports `flutter_tools` as a library (`sdk: flutter`) and adds only what the
targets need on top of `flutter build`.

Pinned to Flutter **3.47.5**; the patch series here are made against it.

## Use

```sh
dart pub global activate --source git https://github.com/p0g-stack/flutter_p0g
# (or --source path <checkout>; run it with the pinned Flutter's dart)

cd my_app
flutter_p0g create .          # adds webui/ and aera/ (and web/ if missing)
flutter_p0g build webui       # build/webui/<id>-v<version>.zip
flutter_p0g install --reboot  # adb + the device's ksud / apd / magisk
flutter_p0g logs              # the module's root process and page console

flutter_p0g build aera        # build/aera/<id>-<version>.aerap
adb reboot recovery
flutter_p0g install --open    # into AERA recovery's plugin store, then open it
```

## Parity

The bar: on WebUI and AERA, the same experience the stock `flutter` tool
gives on an official platform, with the same flags meaning the same things.
Measured against `flutter run` on desktop and against flutterpi_tool.
Gaps are listed here, not hidden.

| Stock `flutter` | WebUI | AERA |
|---|---|---|
| `create --platforms` | `create` adds `webui/` | `create` adds `aera/` |
| `build <target>` (all flags) | `build webui`: every `build web` flag | `build aera`: every `build bundle` flag; debug, profile, release |
| `run` + hot reload / restart | works in Chromium through flutter-webui's `dev.html` on the manager origin; device path (adb reverse, page swap) not yet run on a device | `run --aera`: debug `.aerap` into AERA recovery, started over AERA's RPC with the VM service on a forwarded port, then the stock `flutter attach` (flutter-aera `docs/debugging.md`); checked against a fake adb and a stand-in VM, not yet on a device |
| `attach` | gap | gap (follows the debug engine) |
| `install` | `install`: adb + ksud / apd / magisk; activates on reboot | `install`: into AERA's plugin store as its Plugin Manager does, `--open` over AERA's RPC; not yet run on a device |
| `devices` | `devices`: adb devices with the root manager probe `install` uses | `devices`: recovery with AERA's RPC channel |
| `logs` | `logs`: the root channel and root process logs plus the page console (logcat `chromium`) | `logs`: AERA's `/tmp/recovery.log` |
| `precache` | web SDK; Android Dart kit; frb; patched Squadron (`--squadron`, also automatic in `build webui` and `run`) | AERA runtime kit |
| `clean`, `doctor`, `test` | gap (stock `flutter test` works; no target tests) | gap |

## Commands

| Command | What it does | State |
|---|---|---|
| `create [dir]` | Adds `webui/` (module.prop, customize.sh, `webroot/config.json` with flutter-webui's `docs/hosts.md` settings) and `aera/` (the app's part of plugin.json), like `flutter create --platforms` | works |
| `build webui` | `flutter build web` with WebUI defaults, then the module zip. Every `build web` flag works | works |
| `build aera` | `flutter build bundle` (+ AOT `libapp.so` for profile/release) packed with flutter-aera's runtime kit into a `.aerap` | works; debug against the released arm64 kit (kit-3.47.5) |
| `install [zip\|aerap]` | Module zip: `adb push`, then the first installer present on the device (`ksud`, `apd`, `magisk`). `.aerap` (device in recovery): see below | works against a fake adb; not yet run on a device |
| `devices` | `adb devices -l`, each probed for a root manager (booted) or AERA's RPC channel (recovery) | works against a fake adb |
| `logs` | Booted: `tail -F` of the module's `webroot/.run/root.log` and newest `proc/*.log` (flutter-webui `docs/root-channel.md`) plus `logcat chromium:V`. Recovery: `/tmp/recovery.log` | not yet run on a device |
| `run` | `flutter run -d web-server` (DDC, hot reload/restart, debug service) with the patched SDK and the flutter_webui plugin, behind a dev proxy; with adb, reverses the port and points the installed module's page at it | works in Chromium; device path not yet run |
| `precache` | Flutter's web SDK and flutter-webui (`--webui`, with fallback fonts); `--webui-packages`; `--app-plane` (pinned APK); `--frb` builds the patched frb; `--dart-android` and `--aera-kit` install kits; `--squadron` | works |

### `build webui`

1. If the app has `flutter_rust_bridge.yaml`: the patched frb's
   `build-web --no-threads` (single-threaded wasm, runs without COOP/COEP).
2. flutter-webui at its pin (`precache --webui`, run on first use):
   `flutter build web` compiles against its patched web SDK (pointed to
   through flutter_tools' artifacts, so `bin/cache` stays stock) and its
   bootstrap replaces the page (`index.html` with the module id and name,
   `flutter_bootstrap.js` filled with the build config, `flutter_webui.js`,
   `flutter_webui.css`).
   The flutter_webui web plugin (the engine handlers) is added for the build
   only, since apps depend on `flutter_webui_client` alone: its packages
   (from flutter-webui's own resolution) join the package config while the
   build runs, and the target becomes a generated main that calls
   `FlutterWebUi.registerWith` before the app's `main()`, as flutter-tizen
   registers its embedding plugins. Packages the app already resolves stay
   its own.
   For each plugin the app uses that webui-packages implements (`*_webui`,
   pinned, `precache --webui-packages`), the build also makes the `*_webui`
   package a direct dependency: Flutter registers one web implementation per
   plugin, and a `*_webui` one wins over the stock `*_web` only as a direct
   dependency (webui-packages `docs/plugins.md`). The package config, the
   package graph and the manifest flutter_tools sees all carry it while the
   build runs; `pubspec.yaml` and the lockfile are not touched.
3. `flutter build web`, defaulting to `--no-web-resources-cdn` (CanvasKit and
   fonts bundled; managers can't rely on a CDN) and no service worker.
4. Prunes what a manager never loads: `*.symbols`, the service worker,
   `webparagraph/`, `wimp.*`, and Skwasm unless `--wasm`.
5. Squadron Web Workers: every generated `*.web.g.dart` in the app or its
   workspace packages is compiled (`dart compile js`, `wasm` with `--wasm`)
   to the `~/workers/...` path its activator loads, inside `webroot/`.
6. web_ui's fallback fonts (Roboto, Noto Sans, emoji, symbols, math; about
   3 MB, fetched once by `precache --webui`) in `webroot/fonts/`, where the
   bootstrap points the engine: a manager WebView has no system fonts.
7. flutter-webui's root channel (`docs/root-channel.md`): `flutter_webui/root`
   and, per ABI, `flutter_webui/<abi>/{flutter_webui_root.aot,dartaotruntime}`
   (compiled as below). `customize.sh` gets a generated block making the
   tool's program directories executable.
   The module's data folder is `/data/adb/<id>/` (the app's support,
   documents, cache and temp directories). `customize.sh` gets a generated
   block: a fresh install (no `/data/adb/modules/<id>` yet) removes a leftover
   `/data/adb/<id>`, an update keeps it, and both set `webui.installed` in
   KernelSU's `ksud module config` (KernelSU or KernelSU Next 3.0+; ksud clears
   it on uninstall). `uninstall.sh` ends with the fixed line
   `MODPATH=${0%/*}; rm -rf "/data/adb/${MODPATH##*/}"`, after the app's own
   `webui/uninstall.sh` if it has one.
8. With `webui_app_plane` in the build (a `*_webui` plugin brings it): the app
   plane, `webui_app_plane/termux-api`, `webui_app_plane/<abi>/webui_termux_api.aot`
   and the module's own copy of the webui-termux-api APK. The base release is
   pinned by tag and sha256 in `lib/src/webui/app_plane.dart` (`precache
   --app-plane`); the build renames it to `com.webui.api.<seg>` (`<seg>` is the
   module id with characters outside `[A-Za-z0-9_]` turned into `_`, and an `m`
   in front of a leading digit), labels it with module.prop's `name`, and puts
   it at `system/product/app/WebuiApi_<seg>/WebuiApi_<seg>.apk`. So Android's
   permission dialog names the module, and grants and data are per module.
   The APK is re-signed (APK Signature Scheme v2, no JDK needed) the way a
   stock Flutter Android build picks a key:
   - `webui/key.properties`, else `android/key.properties` (`storeFile`,
     `storePassword`, `keyAlias`, `keyPassword`; `storeFile` relative to
     `webui/`, or to `android/app/` then `android/`). The keystore must be
     PKCS12 (keytool's default since JDK 9); a JKS one is refused with the
     `keytool -importkeystore` line that converts it.
   - Otherwise the debug key in `~/.android/debug.keystore`
     (`$ANDROID_USER_HOME/debug.keystore`), created if missing; a JKS debug
     keystore makes the build use one in the flutter_p0g cache instead.

   **Releases need a stable key.** Android keeps an app's permission grants
   and data only while updates carry the same signing key, and debug keys
   differ per machine. A CI that publishes modules must write a
   `webui/key.properties` from its secrets (keystore and passwords) before
   `build webui`; changing the key later means users must uninstall the old
   copy and grant again.
9. If the app or its workspace root has `cli/` (the bricks layout): compiles it
   for the device into `bin/`, with the frb `.so` from `rust/` beside it
   (`--device-rust-libs=<dir>` takes libraries built elsewhere, laid out as
   `<dir>/<abi>/*.so`; `--no-device-rust` ships without them).
   See "The root process" below.
10. Zips: web build in `webroot/`, then `webui/` on top (its `webroot/` overlays
   the build), Magisk's installer stub in `META-INF/`. `module.prop`'s
   `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` come from the pubspec
   version or `--build-name` / `--build-number`, as on iOS.
11. Self-update: sets `updateJson` in `module.prop` and writes `update.json`
   (`version`, `versionCode`, `zipUrl`, `changelog`: the format KernelSU,
   APatch and Magisk poll) and `changelog.md` (the app's `CHANGELOG.md`, or a
   version line) beside the zip, so the manager's update button works once a
   release publishes all three. They live under `--update-url`, else the
   directory of an `updateJson` already in `webui/module.prop`, else
   `releases/latest/download/` of the pubspec's GitHub `repository:`. With
   none of those, or `--no-update-json`, the module has no `updateJson`.

A stock counter app gives a 6.3 MB zip (29 files) that loads with no console
errors and no requests outside the module, served at `/` with no COOP/COEP.

### The root process

The app's `cli/` runs as root on the device. Stock Dart can't target Android
from a desktop host (`dart compile exe` and `aot-snapshot` reject
`--target-os android`; the linux-arm64 output links glibc), and an AOT
snapshot only loads in a runtime of its own Dart version, OS and build flags.
So by default (`--cli-format=aot`) the build:

1. compiles `cli/` to AOT kernel with the SDK's own `gen_kernel --aot
   --target-os android` and product platform,
2. turns it into an android-arm64 ELF with the kit's host `gen_snapshot`,
3. ships `bin/<abi>/<name>.aot`, `bin/<abi>/dartaotruntime` and a
   `bin/<name>` launcher that picks the device ABI and sets `TMPDIR` to the
   module's `tmp/` (root shells can start with an empty environment).

The kits (`precache --dart-android [--dart-android-abi=arm64-v8a,x86_64]`), one per ABI, are both halves built from the pinned
Dart release with `tools/build.py --mode product --os android` by
`.github/workflows/dart-android-kit.yml`; `--dart-android-kit=<path|url>`
swaps in another source with the same layout (`VERSION`, `gen_snapshot`,
`dartaotruntime`). The pipeline is checked end to end with a host-arch kit;
the Android kit itself is not built yet. `--cli-format=exe` is kept for a Dart
SDK that can compile Android executables directly.

### `run`

1. flutter_tools' `web-server` device on a free loopback port, built like
   `build webui` (patched web SDK, the flutter_webui plugin, no CDN).
2. A dev server on `--dev-port` (8800) in front of it, per flutter-webui's
   `docs/dev.md`: CORS for the manager's origin (no credentials, `no-store`),
   flutter-webui's `flutter_webui.js`/`.css` and its `flutter_bootstrap.js`
   filled with the build config (the bootstrap itself bases the loader at the
   dev server), web_ui's fallback fonts at `fonts/`, Roboto added to
   `FontManifest.json` as `build web` bundles it, `reloaded_sources.json`
   made absolute, the `Host` header and WebSockets passed through. Checked in
   headless Chromium with the page on `https://mui.kernelsu.org/`: first
   frame, text, hot reload keeping state.
3. With a device on adb (`--serial`): `adb reverse tcp:8800`, and the
   installed module's `index.html` becomes flutter-webui's `dev.html` pointed
   at the proxy (the release page kept as `index.release.html`, put back on
   exit). Without one, open `dev.html?dev=http://127.0.0.1:8800/` from any
   page that serves flutter-webui's bootstrap.

### `run --aera`

With the device in AERA recovery: builds a debug `.aerap` (`build aera
--debug`, or `--aerap <file>`), installs it as `install` does, writes
`--vm-service-port=<port>` (the stock `--vm-service-port`, default 8181) to
the plugin's `engine-switches` in its data directory
(`/sdcard/AERA/plugin-data/<id>`, or `/tmp/aera/plugin-data/<id>` when
`/sdcard/AERA` is absent, as AERA picks it), forwards the port, opens the
plugin over AERA's RPC, waits for `vm-service-url`, and runs the stock
`flutter attach --debug-url <url> -d flutter-tester` in the app. Without a
URL in 30 s it prints the tail of `aera-flutter.log`.

### `build aera`

Follows flutter-aera's `spec/aerap.md`. `flutter build bundle` for
`linux-arm64` (any `build bundle` flag works); debug keeps
`kernel_blob.bin` for a debug (JIT) engine, profile and release add
`usr/lib/libapp.so` from the SDK's frontend server plus the kit's
`gen_snapshot`. The app's `flutter_assets` and the runtime kit's tree become
AERA's runtime stream, xz-compressed with CRC32 and the ARM64 BCJ filter
(XZ Utils 5.4+), and `plugin.json` is the app's `aera/plugin.json` plus the
packer's fixed and computed fields. Output: `build/aera/<id>-<version>.aerap`
and a copy of `plugin.json`.

The kit is flutter-aera's release (`precache --aera [--aera-mode=debug]`
fetches `kit-<flutter>/flutter-aera-kit-linux-arm64-<mode>-<flutter>.tar.xz`
and checks its `.sha256`; `--aera-kit=<path|url>` installs another). Its
`kit.json` must name the pinned engine revision and stays out of the
payload, as does `host/gen_snapshot`, which profile and release kits need
(only a debug kit is released so far). Checked: a debug
`.aerap` of the counter app, built against a linux-x64 kit of the pinned
debug engine, expands and runs in flutter-aera's `aera-host-sim` (taps
count).

### `install` for AERA

With the device in AERA recovery (adb runs as root there), `install` does
what AERA's Plugin Manager does for a local `.aerap` (`InstallLocal()` in
`aeraui/features/plugins/plugin_manager.cpp` at `abf3316`). It checks the
package as `OpenLocalBundle()` does, then pushes `plugin.json`,
`runtime.xz` and the signature, if there is one. On the device it stages
them, checks the payload's sha256, makes the files 0444, and renames the
staging directory to `/sdcard/AERA/plugins/<id>`, or to
`/tmp/aera/plugins/<id>` with `--ram`. A previous install is kept until
that rename succeeds. Installing this way skips the Plugin Manager's
"unofficial plugin" prompt, as `adb install` skips Android's.

`--open` sends `{"v":1,"op":"plugin","args":{"action":"open","id":…}}` to
AERA's RPC FIFOs (`/system/bin/aerain`, `/system/bin/aeraout`). The
`plugin` operation comes from flutter-aera's Host API 3 patch 0008; stock
AERA answers `unsupported_operation`.

## frb patches

`patches/frb/` holds the series applied to
[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) at
`848e438` (master just after v2.14.0-beta.2; the series doesn't apply to
the tag). `precache --frb` fetches that commit, applies the series in order and
builds the codegen into `<flutter>/bin/cache/flutter_p0g/frb/`. Nothing is
upstreamed until it has been tested on its own.

| Patch | What | State |
|---|---|---|
| `0001-build-web-no-threads` | `build-web --no-threads`, the `LocalKey` thread-pool stub, a clear error for plain fns | standalone-tested 2026-09-30 (Chromium, no COOP/COEP) |
| `0002` JSPI | | planned |
| `0003-web-worker-init` | the wasm binding from `globalThis` (not `window`) and module init inside Web Workers, so a Squadron worker can load the crate | from the demo thread (page 3); applies after 0001, not yet standalone-tested |

An app using frb points its Dart dependency at the patched copy (the build
says so if it doesn't):

```yaml
dependency_overrides:
  flutter_rust_bridge:
    path: <flutter>/bin/cache/flutter_p0g/frb/src/frb_dart
```

and its crate at `frb_rust` (`[patch.crates-io]`) with
`default-features = false` plus `anyhow, dart-opaque, log, portable-atomic,
rust-async, user-utils, wasm-start`. Exports must be `#[frb(sync)]` or
`async fn`, or set `default_dart_async: false`.

## Squadron patches

`squadron_process` owns its Squadron series (`third_party/squadron/`) and the
tool that applies it (`squadron_process:squadron_patch`, which writes the
workspace's `pubspec_overrides.yaml`). `build webui`, `run` and
`precache --squadron` run that tool in the workspace member that depends on
`squadron_process`, then `pub get`, unless something already overrides
`squadron`.

## Layout

```
bin/flutter_p0g.dart       entrypoint
lib/src/executable.dart    runner inside flutter_tools' context
lib/src/commands/          create, build (webui, aera), install, run, devices, logs, precache
lib/src/adb.dart           adb helpers
lib/src/aera/              .aerap packer, AERA install and RPC
lib/src/webui/             module assembly and zip, cli/ compile
lib/src/frb/               pinned frb, patch apply, build-web
lib/src/templates.dart     webui/ and aera/ platform folders
patches/frb/               the frb series
test/                      unit tests (no e2e)
```

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
