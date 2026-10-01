# bricks

> Formerly `template-app`.

[Mason](https://pub.dev/packages/mason) bricks for p0g-stack apps. Platform
folders are not here: `flutter_p0g create .` adds `webui/` and `aera/` to
any Flutter app, the way `flutter create --platforms` does.

## Bricks

| Brick | Stamps |
|---|---|
| `p0g_app` | a pub workspace: `core/` (pure Dart, the logic), `app/` (Flutter GUI on core), `cli/` (Dart CLI on core, `dart compile exe`; also the WebUI root process in serve mode), optional `rust/` via frb for crates the core uses; Squadron + `squadron_process`; logging convention |
| `service` | a Squadron service exposed to both the GUI (a panel) and the CLI (a command and `serve`) |
| `strategy` | an objective and its strategies, chosen by `available(facts)` (e.g. on-device `dd` vs host `fastboot fetch`); device writes plan, confirm, receipt |

`packages/p0g_lints` is an analyzer plugin the generated workspace turns on:
`core_imports_flutter` and `strategy_reads_platform` make the two main
conventions `dart analyze` warnings.

A new app, step by step to a WebUI module: [docs/new-app.md](docs/new-app.md).
A worked objective, CBM's partition fetch (`dd` on the device against
`fastboot fetch` from a computer):
[docs/samples/partition-fetch.md](docs/samples/partition-fetch.md).

In short:

```sh
dart pub global activate mason_cli
mason add p0g_app --git-url https://github.com/p0g-stack/bricks --git-path bricks/p0g_app
mason make p0g_app
cd <name> && bash tool/bootstrap.sh
flutter_p0g create .     # webui/ and aera/
```

Then add to it from the workspace root:

```sh
mason add service --git-url https://github.com/p0g-stack/bricks --git-path bricks/service
mason add strategy --git-url https://github.com/p0g-stack/bricks --git-path bricks/strategy
mason make service --name partitions
mason make strategy --name fetch_partition --strategies '["dd", "fastboot fetch"]'
```

and build with `flutter_p0g build webui` / `aera`. Each brick's
README lists its variables; `bricks/<brick>/CHANGELOG.md` its versions.

## Pins

Flutter 3.47.5 (Dart 3.13), Squadron 7.4.4 (patched, via squadron_process)
with squadron_builder 9.3.2, squadron_process and flutter-webui (`flutter_webui_client`) by commit,
flutter_rust_bridge 2.14.0-beta.2 (the base of flutter_p0g's frb patches),
mason_cli 0.1.4.

## CI

`tool/ci.sh` generates `p0g_app`, adds a service and two objectives (read and
write) to it, bootstraps it, and
runs the generated workspace's analyzer, unit and widget tests (including a
service running in the CLI as a process place), the CLI executable, and the
web and Linux builds; the `rust` variant does the same plus `cargo test`,
and checks that the CLI executable loads the library beside it and hashes
with Rust. No e2e. `.github/workflows/ci.yaml` runs it on every push.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
