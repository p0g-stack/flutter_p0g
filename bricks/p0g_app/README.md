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
- `cli/`: `package:args`. `hello`, `facts`, `serve <service>` (squadron_process
  host). `-v` and `--json` control logging.
- `tool/`: `bootstrap.sh` (patched Squadron, pub get, codegen,
  `flutter create` for linux and web, web workers, format), `squadron.sh`,
  `build_workers.sh`.

squadron_process is a git dependency pinned by commit, with the patched
Squadron it needs through `pubspec_overrides.yaml`, until it publishes and
flutter_p0g handles the patch. Its API is used only in `cli/.../serve_command.dart`,
`app/lib/places/` and `core/lib/src/facts/facts.dart`.

The WebUI launcher's contract with the root channel: [docs/webui-launch.md](../../docs/webui-launch.md).
It is written against `RootChannelClient`, the documented shape of
flutter-webui's page client, because that client is not published yet; until
it is, nothing sets `rootChannel` and WebUI runs services in Web Workers.

Generated code (`*.g.dart`, compiled workers) is not committed; bootstrap
regenerates it.
