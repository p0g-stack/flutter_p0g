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

## Commands

| Command | What it does | State |
|---|---|---|
| `create [dir]` | Adds `webui/` (module.prop, customize.sh, `webroot/config.json`) and `aera/` (plugin.json), like `flutter create --platforms` | works |
| `build webui` | `flutter build web` with WebUI defaults, then the module zip. Every `build web` flag works | works |
| `build aera` | `.aerap` | stub: waits on the layout and engine kits from flutter-aera |
| `install [zip]` | `adb push`, then the first installer present on the device: `ksud`, `apd`, `magisk` | works, not yet run on a device |
| `run` | dev loop with hot restart | stub: waits on flutter-webui's bootstrap |
| `precache` | Flutter's web SDK; `--frb` builds the patched frb | web and frb work; `--aera`, `--app-plane` wait on releases |

### `build webui`

1. If the app has `flutter_rust_bridge.yaml`: the patched frb's
   `build-web --no-threads` (single-threaded wasm, runs without COOP/COEP).
2. `flutter build web`, defaulting to `--no-web-resources-cdn` (CanvasKit and
   fonts bundled; managers can't rely on a CDN) and no service worker.
3. Prunes what a manager never loads: `*.symbols`, the service worker,
   `webparagraph/`, `wimp.*`, and Skwasm unless `--wasm`.
4. If the app or its workspace root has `cli/` (the bricks layout): compiles it
   for the device into `bin/`, with the frb `.so` from `rust/` beside it.
   See "The root process" below.
5. Zips: web build in `webroot/`, then `webui/` on top (its `webroot/` overlays
   the build), Magisk's installer stub in `META-INF/`. `module.prop`'s
   `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` come from the pubspec
   version or `--build-name` / `--build-number`, as on iOS.

A stock counter app gives a 6.3 MB zip (29 files) that loads with no console
errors and no requests outside the module, served at `/` with no COOP/COEP.

### The root process

The app's `cli/` is meant to be a `dart compile exe` binary running as root on
bionic. Dart 3.13 can't produce one from this host: `dart compile exe
--target-os android` is rejected, and the `linux-arm64` output links glibc
(`/lib/ld-linux-aarch64.so.1`), which Android doesn't have. So `build webui`
fails with that explanation when `cli/` is present. Apps without `cli/`
(stock apps) are unaffected.

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
