# p0g_app

A p0g-stack app as one pub workspace.

```sh
mason make p0g_app
cd <name> && bash tool/bootstrap.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `name` | `my_app` | package prefix (`<name>_core`, `<name>_app`, `<name>_cli`) and CLI executable |
| `description` | `A p0g-stack app.` | one line for READMEs and `--help` |
| `org` | `com.example` | passed to `flutter create` for the stock platform folders |
| `rust` | `false` | adds `rust/` and `flutter_rust_bridge.yaml` (frb `=2.14.0-beta.2`, the base of flutter_p0g's patch series) |
| `process_place` | `false` | adds `squadron_process` (git, until it publishes), the CLI `serve` command and `ProcessLink` in the app |

What it stamps:

- `core/`: pure Dart. `Facts` and `Fact` keys, `Place`, `Objective` with
  `ReadStrategy` / `WriteStrategy` (`available(facts)`; plan, confirm,
  receipt), the logging convention (`StrategyRun`, `logTo`), and an example
  Squadron service, `HelloService`.
- `app/`: Flutter. `places.dart` opens a place (Squadron's isolate or Web
  Worker, or the process place) and starts workers there; a home page shows
  the place, its facts, the service and the log.
- `cli/`: `package:args`. `hello`, `facts` (probed, not guessed), and `serve` with `process_place`.
  `-v` and `--json` control logging.
- `tool/bootstrap.sh`: pub get, Squadron codegen, `flutter create` for
  linux and web, web worker compilation.

Generated code (`*.g.dart`, compiled workers) is not committed; bootstrap
regenerates it.

## Assumed squadron_process API

Only `cli/lib/src/commands/serve_command.dart` and `app/lib/places.dart`
touch it, and only when `process_place` is on:

- `serveProcess(services: {'hello': $HelloServiceInitializer}, facts: Map, port: int, grace: Duration, onListening: void Function(Uri))`
- `ProcessPlace.connect(Uri)`, then `place.facts` (Map), `place.start(serviceName, WorkerConstructor)`, `place.close()`

The WebUI launcher (starting `<name> serve` through flutter-webui's root
channel) is wired here once `flutter_webui_root` has a client API; until then
the app takes the endpoint from `--dart-define=P0G_PROCESS_ENDPOINT=...`.
