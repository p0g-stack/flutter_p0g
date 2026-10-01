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
