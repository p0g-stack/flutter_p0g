# p0g_app

A p0g-stack app as one pub workspace.

```sh
mason make p0g_app
cd <name> && bash tool/bootstrap.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `name` | `my_app` | package prefix (`<name>_core`, `<name>_cli`), the app package and the CLI executable |
| `description` | `A p0g-stack app.` | one line for READMEs and `--help` |
| `org` | `com.example` | passed to `flutter create` for the stock platform folders |
| `rust` | `false` | adds `rust/` and `flutter_rust_bridge.yaml` (frb `=2.14.0-beta.2`, the base of flutter_p0g's patch series) |

What it stamps:

- `core/`: pure Dart. The fact keys and their checks (`dart:io` and browser),
  `Facts` (squadron_process's `PlaceFacts`) and `PlaceInfo`; `Objective` with
  `ReadStrategy` / `WriteStrategy` (`available(facts)` from `requires`, a
  `Selection` that says why; plan, confirm, receipt); the logging convention
  (`StrategyRun`, `logTo`); an example Squadron service, `HelloService`.
- `app/`: Flutter. `places/` (Squadron's own place, the process place where a
  launcher exists: `P0G_CLI` on a desktop, the WebUI launcher over
  flutter-webui's root channel), `panels/` (one per service), a home page
  with a place picker and the log.
- `cli/`: `package:args`. `hello`, `facts`, `serve` (squadron_process host
  for every service, by name). `-v` and `--json` control logging.
- `tool/`: `bootstrap.sh` (patched Squadron, pub get, codegen,
  `flutter create` for linux and web, web workers, format) and
  `build_workers.sh`.

squadron_process and flutter_webui_client are git dependencies pinned by commit.
squadron_process needs Squadron with its channel-factory patch: bootstrap
runs `dart run squadron_process:squadron_patch`, which fetches the patched
copy into `.dart_tool/` and writes `pubspec_overrides.yaml` (gitignored),
until it is upstream or flutter_p0g handles it. squadron_process's API is used
only in `cli/.../serve_command.dart`, `app/lib/places/`,
`core/lib/src/places/` and `core/lib/src/facts/facts.dart`.

The WebUI launcher (`core/lib/src/places/webui_launcher.dart`) starts the CLI
through flutter-webui's root channel with `flutter_webui_client`, plain Dart
that builds on a stock SDK. The app never depends on the `flutter_webui` web
plugin (engine handlers only); flutter_p0g adds it when it builds for WebUI.
`cli/test/webui_launch_test.dart` runs the launch against the real
`flutter_webui_root` on the VM. Its contract with the root channel is
[docs/webui-launch.md](../../docs/webui-launch.md). In a plain browser there is
no process place, and services run in Web Workers.

One app, one CLI: `cli/` is the app's only command line, compiled per OS
and ABI (`dart compile exe` on desktops, an AOT snapshot plus
`<abi>/dartaotruntime` on Android via flutter_p0g). Rust crates come in
through frb inside that CLI and the app; the `rust/` crate is a library and
never ships its own binary or CLI.

With `rust`, the crate is a working example: `sha256_hex` through the `sha2`
crate, called by the `digest` objective (`core/lib/src/strategy/digest.dart`),
whose Rust strategy requires the `native` fact and whose Dart strategy is the
fallback. `loadNative()` (`core/lib/src/native/`) loads the library once per
isolate, Web Worker or process: `P0G_NATIVE_LIB`, then beside the executable
(`bin/<abi>/` where flutter_p0g packs it, or beside a `dart compile exe`
binary), then a Linux bundle's `lib/`, then `rust/target/` in the workspace.
On the web it is frb's wasm under `pkg/`, checked with a HEAD request for the
`native` fact and instantiated on the first Rust call, which `flutter_p0g build webui`
builds; a plain `flutter build web` has none, and the Dart strategy runs.
The hello service's `sha256`, the CLI's `digest` command and the app's
SHA-256 button go through it. `tool/rust.sh` (run by bootstrap) uses
flutter_p0g's patched frb when `flutter_p0g precache --frb` has built it,
native and wasm; otherwise `flutter_rust_bridge_codegen` built from frb
848e438 (the commit both sides pin), native only. It also needs cargo-expand.

Generated code (`*.g.dart`, compiled workers) is not committed; bootstrap
regenerates it.
