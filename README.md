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
| `run` + hot reload / restart | gap: needs flutter-webui's dev loader (plan: web dev server over adb reverse, a dev module pointing at it) | gap: needs flutter-aera's debug engine with the VM service URL in its log |
| `attach` | gap | gap (follows the debug engine) |
| `install` | `install`: adb + ksud / apd / magisk; activates on reboot | gap: no `.aerap` install path yet |
| `devices` | gap (adb devices with a root manager probe) | gap |
| `logs` | gap | gap |
| `precache` | web SDK; Android Dart kit; frb | AERA runtime kit |
| `clean`, `doctor`, `test` | gap (stock `flutter test` works; no target tests) | gap |

## Commands

| Command | What it does | State |
|---|---|---|
| `create [dir]` | Adds `webui/` (module.prop, customize.sh, `webroot/config.json` with flutter-webui's `docs/hosts.md` settings) and `aera/` (the app's part of plugin.json), like `flutter create --platforms` | works |
| `build webui` | `flutter build web` with WebUI defaults, then the module zip. Every `build web` flag works | works |
| `build aera` | `flutter build bundle` (+ AOT `libapp.so` for profile/release) packed with flutter-aera's runtime kit into a `.aerap` | works; debug against the released arm64 kit (kit-3.47.5) |
| `install [zip]` | `adb push`, then the first installer present on the device: `ksud`, `apd`, `magisk` | works, not yet run on a device |
| `run` | dev loop with hot restart | stub: waits on flutter-webui's bootstrap |
| `precache` | Flutter's web SDK; `--frb` builds the patched frb; `--dart-android` and `--aera-kit` install kits | works; the kit releases and `--app-plane` wait on CI |

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
3. `flutter build web`, defaulting to `--no-web-resources-cdn` (CanvasKit and
   fonts bundled; managers can't rely on a CDN) and no service worker.
4. Prunes what a manager never loads: `*.symbols`, the service worker,
   `webparagraph/`, `wimp.*`, and Skwasm unless `--wasm`.
5. Squadron Web Workers: every generated `*.web.g.dart` in the app or its
   workspace packages is compiled (`dart compile js`, `wasm` with `--wasm`)
   to the `~/workers/...` path its activator loads, inside `webroot/`.
6. If the app or its workspace root has `cli/` (the bricks layout): compiles it
   for the device into `bin/`, with the frb `.so` from `rust/` beside it.
   See "The root process" below.
7. Zips: web build in `webroot/`, then `webui/` on top (its `webroot/` overlays
   the build), Magisk's installer stub in `META-INF/`. `module.prop`'s
   `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` come from the pubspec
   version or `--build-name` / `--build-number`, as on iOS.

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
| `0003` worker init | | planned |

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

## Squadron patches (planned)

`squadron_process` needs Squadron 7.4.4 with a `Worker.channelFactory` patch.
Its series will live in `patches/squadron/` and be applied and cached like
frb's; until then the app overrides the dependency itself.

## Layout

```
bin/flutter_p0g.dart       entrypoint
lib/src/executable.dart    runner inside flutter_tools' context
lib/src/commands/          create, build (webui, aera), install, run, precache
lib/src/webui/             module assembly and zip, cli/ compile
lib/src/frb/               pinned frb, patch apply, build-web
lib/src/templates.dart     webui/ and aera/ platform folders
patches/frb/               the frb series
patches/squadron/          the Squadron series (planned)
test/                      unit tests (no e2e)
```

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
