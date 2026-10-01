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

squadron_process and flutter_webui are git dependencies pinned by commit.
squadron_process needs Squadron with its channel-factory patch: bootstrap
runs `dart run squadron_process:squadron_patch`, which fetches the patched
copy into `.dart_tool/` and writes `pubspec_overrides.yaml` (gitignored),
until it is upstream or flutter_p0g handles it. squadron_process's API is used
only in `cli/.../serve_command.dart`, `app/lib/places/` and
`core/lib/src/facts/facts.dart`.

The WebUI launcher (`app/lib/places/webui_launcher.dart`) starts the CLI
through flutter-webui's root channel, behind `WebUiRoot`, the few calls of
flutter_webui's `RootChannel` it uses. The app does not depend on
flutter_webui, a web plugin that needs flutter-webui's patched engine (a stock
`flutter build web` would not compile); the WebUI target sets `webUiRoot`
from its own glue. Its contract with the root channel is
[docs/webui-launch.md](../../docs/webui-launch.md). In a plain browser there is
no process place, and services run in Web Workers.

One app, one CLI: `cli/` is the app's only command line, compiled per OS
and ABI (`dart compile exe` on desktops, an AOT snapshot plus
`<abi>/dartaotruntime` on Android via flutter_p0g). Rust crates come in
through frb inside that CLI and the app; the `rust/` crate is a library and
never ships its own binary or CLI.

Generated code (`*.g.dart`, compiled workers) is not committed; bootstrap
regenerates it.
