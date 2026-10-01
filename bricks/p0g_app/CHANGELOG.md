# 0.8.2

- squadron_process 28c37ce: each service log record reaches a page once,
  however many workers it binds (5d41a99 sent one copy per link). The launch
  test binds two workers and checks for one copy.

# 0.8.1

- squadron_process 5d41a99: the host relays service log records over the
  process link, so `withLogs` workers bound to the process place log them on
  the page too. The CLI's WebUI launch test checks it end to end.

# 0.8.0

- flutter-webui bebb1ec (root channel 0.2.0): `root start` prints the
  session and the channel keeps its state out of `webroot/`. The app's
  process place follows: its session file moves from
  `webroot/.run/<app>.place.json` to `<module>/run/<app>.place.json`, so the
  token is no longer on the manager's HTTP origin. The CLI's launch test
  starts the channel the new way.
- Logs come back from services. A service's constructor calls
  `forwardLogs()`, and callers wrap workers in `withLogs(...)` (the panels
  and `serve` do). Records from a worker now reach the app's log, and those
  from services in the CLI's `serve` reach the CLI's log, under their own
  logger names. Carrying them from the process place to the page waits on
  squadron_process.
- `Places.lasting`: the process place when there is one. Work that must
  keep going while the page is hidden or rotated goes there, never to a Web
  Worker (docs/patterns/places.md).
- docs/patterns/files.md in bricks: saving a file per target. On WebUI,
  use `getSaveLocation` and then `WebUiRoot.writeFile` (or `dart:io` in the
  process place), followed by `AppPlane.scanMedia`. Never `XFile.saveTo`.

# 0.7.4

- `rust` on the web: the `native` fact asks for the small JS glue
  (`pkg/<stem>.js`), not the wasm. Manager WebViews answer a HEAD with the
  whole file, so the old check downloaded the wasm at start anyway.

# 0.7.3

- flutter-webui 9c5c631: KernelSU brightness follows the manager's theme
  colours, and the client carries the colour calls dynamic_color_webui
  uses (flutter_p0g builds with them).

# 0.7.2

- The app takes the host's colours through the stock `dynamic_color`
  builder: Material You on Android, the accent colour on desktop, and, once
  flutter_p0g adds `dynamic_color_webui`, the manager's colours in a WebUI.
  Without them (a plain tab, AERA, tests) it keeps its own scheme from
  `seed` in `app/lib/theme.dart`. To opt out, have `hostColors` call
  `builder(null, null)` and drop `dynamic_color`.

# 0.7.1

- `rust` on the web: the Rust wasm loads on the first Rust call, not at
  start. The `native` fact asks whether the wasm is there (a HEAD request,
  `nativeShipped()`); a strategy that calls Rust awaits `loadNative()` first
  (the `digest` example does). Native places still load the library for the
  fact, which is cheap.

# 0.7.0

- `Availability.waiting`: a strategy that would run once the user acts
  (connect a phone) says so. It isn't chosen; `Selection.waiting` lists it
  for the UI and `Selection.why` logs "x waits: ...". Missing facts win.
- `WriteStrategy`'s doc comment: a write to a device outside this place
  names the device in its input and refuses if another is connected.
- docs/patterns/devices.md in bricks: the device-app patterns.

# 0.6.6

- flutter-webui 9ee7918: on KernelSU Next, Back at the root route unwinds
  history and the next Back closes the WebUI, as in a browser tab.

# 0.6.5

- flutter-webui 8deba51: Back from a pushed route no longer closes the whole
  WebUI in KernelSU 3.3.0.

# 0.6.4

- `block_devices` was false everywhere, root included: dart:io's `File.open`
  accepts only regular files, character devices and pipes, and reports a
  block device as not found. The check now opens through libc
  (`core/lib/src/facts/posix_open.dart`, `package:ffi`), any device that
  opens counts.

# 0.6.3

- flutter-webui 020ab92: Back at the root route works in WebUI X. The fix is
  in the patched web SDK (flutter_p0g rebuilds it); no Dart change here.

# 0.6.2

- flutter-webui 9342a42: host detection survives a throwing
  `ksu.moduleInfo()` (WebUI X v438).
- `openProcessPlace` on the web catches anything host detection throws and
  starts without a process place, so a host bridge can't block the first
  frame.

# 0.6.1

- `rust`: a Squadron Web Worker loads the wasm from `../pkg/` (it runs from
  `workers/`), so the `native` fact holds there too. `tool/rust.sh` builds
  release, the profile the loader tries first, so a stale release build no
  longer shadows a fresh debug one.
- `cli/test/webui_launch_test.dart` is format-clean as stamped.

# 0.6.0

- `analysis_options.yaml` turns on the p0g_lints plugin (this repo,
  `packages/p0g_lints`, pinned by commit): `core_imports_flutter` and
  `strategy_reads_platform` are warnings. `app/analysis_options.yaml`
  includes the root file so they apply in the app too.
- squadron_process d6c561b: reconnect after a dropped link, concurrent
  clients, malformed-handshake hardening.
- `rust` follows flutter_p0g's frb (the demo's four fixes): frb_dart by git at
  848e438, `auto_upgrade_dependency: false`, frb without thread-pool for the
  single-threaded wasm, `mod frb_generated;` after lib.rs's docs. New
  `tool/rust.sh` (run by bootstrap) uses flutter_p0g's patched frb when
  built (native and wasm), else frb at 848e438 (native only), linked through
  gitignored `rust/.cargo/config.toml` and `pubspec_overrides.yaml`.

# 0.5.0

- `rust`: a working crate end to end. `sha256_hex` (the `sha2` crate) behind
  the `digest` objective: a Rust strategy that requires the new `native` fact
  and a Dart fallback (`package:crypto`). `loadNative()` loads the library per
  place (env, beside the executable as flutter_p0g packs `bin/<abi>/`, a
  Linux bundle's `lib/`, `rust/target/`; frb's wasm on the web). Used by the
  hello service (`sha256`), a CLI `digest` command and an app button; tested
  in core, in an isolate, in the serve process and in a compiled CLI.
- Bootstrap runs frb codegen and `cargo build` when `rust` is on.

# 0.4.0

- The WebUI launcher moves to `core/lib/src/places/webui_launcher.dart` and
  depends on flutter-webui's `flutter_webui_client` (git, pinned), plain
  Dart on a stock SDK. `WebUiRoot` and the `webUiRoot` global are gone: on
  web, `openProcessPlace` uses `WebUi.host.moduleDir` and
  `WebUi.connectRootChannel`; a closed channel is reopened on next use.
- New `cli/test/webui_launch_test.dart`: the hello service in the CLI started
  through the real `flutter_webui_root` channel (dev dependency) on the VM.

# 0.3.0

- squadron_process 52ee2f6: one `serve` process hosts every service by name
  (`serve` takes the generated workers); workers bind with `service:`.
- Patched Squadron through `dart run squadron_process:squadron_patch` in
  bootstrap (writes the gitignored `pubspec_overrides.yaml`); `tool/squadron.sh`
  and `.p0g/` are gone.
- The WebUI launcher matches flutter_webui's `RootChannel` (29e692a) behind
  `WebUiRoot`, set by the WebUI target's glue: depending on flutter_webui
  directly breaks a stock `flutter build web` (it needs the patched engine).
  A plain browser has no process place. Tests for the launcher and store.
- Desktop session file under `$XDG_RUNTIME_DIR/<app>/` (else mkdtemp).
- README and AGENTS.md: one app, one CLI; Rust only through frb inside it.

# 0.2.0

- Built on squadron_process (git, pinned) with the patched Squadron through
  `pubspec_overrides.yaml` and `tool/squadron.sh`; the `process_place`
  variable is gone, the process place is always there.
- Layout follows the demo: `core/lib/src/{facts,service,strategy}/`, the app
  package is `<name>`, `tool/build_workers.sh`.
- Facts: the keys and their checks live in core (`checkFacts`, `dart:io`
  and browser); squadron_process carries them as a neutral map.
- Strategies declare `requires`; `available(facts)` returns an
  `Availability`, and a `Selection` says what was skipped and why, which
  `StrategyRun` logs.
- CLI `serve <service>` hosts one service for the process place; the app has
  a place picker, per-service panels, a desktop launcher (`P0G_CLI`) and the
  WebUI launcher (`WebUiLauncher`, `WebUiSessionStore`) over a
  `RootChannelClient`.

# 0.1.0

- Initial brick: pub workspace with `core/` (pure Dart), `app/` (Flutter), `cli/`
  (Dart CLI on package:args with `serve` when `process_place` is on), optional
  `rust/` via flutter_rust_bridge, Squadron with a `hello` service, facts,
  objectives and strategies (`available(facts)`, plan, confirm, receipt), and
  the logging convention.
