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

`../pkgs/p0g_lints` is an analyzer plugin the generated workspace turns on:
`core_imports_flutter` and `strategy_reads_platform` make the two main
conventions `dart analyze` warnings.

A new app, step by step to a WebUI module: [docs/new-app.md](docs/new-app.md).
A worked objective, CBM's partition fetch (`dd` on the device against
`fastboot fetch` from a computer):
[docs/samples/partition-fetch.md](docs/samples/partition-fetch.md).

Apps that talk to a phone over a cable: [docs/patterns/devices.md](docs/patterns/devices.md).
Which place runs what, and how logs come back: [docs/patterns/places.md](docs/patterns/places.md).
Saving a file on every target: [docs/patterns/files.md](docs/patterns/files.md).
Apps in a browser tab (long jobs, files to workers, wasm, writes): [docs/patterns/web.md](docs/patterns/web.md).

In short:

```sh
dart pub global activate mason_cli
mason add -g p0g_app --git-url https://github.com/p0g-stack/p0g --git-path bricks/p0g_app --git-ref p0g-v<x.y.z>
mason make p0g_app
cd <name> && bash tool/bootstrap.sh
cd app && flutter_p0g create .     # webui/ and aera/
```

`flutter_p0g create .` belongs in `app/`: that is the Flutter app; the
workspace root only holds `core/`, `app/` and `cli/`.

Then add to it from the workspace root:

```sh
mason add -g service --git-url https://github.com/p0g-stack/p0g --git-path bricks/service --git-ref p0g-v<x.y.z>
mason add -g strategy --git-url https://github.com/p0g-stack/p0g --git-path bricks/strategy --git-ref p0g-v<x.y.z>
mason make service --name partitions
mason make strategy --name fetch_partition --strategies '["dd", "fastboot fetch"]'
```

Build the module from `app/` with `flutter_p0g build webui`, and the recovery
plugin with `flutter_p0g build aera`. Each brick's README lists its
variables; `bricks/<brick>/CHANGELOG.md` its versions.

## Versions

Bricks have their own versions, independent of the packages: a brick change
bumps the brick and appends a `CHANGELOG.md` line. The generated workspace
pins the packages it uses by the `p0g-v<x.y.z>` tag and names the Flutter
release in `.fvmrc`; there is no separate list to keep in step. A new tag
makes the bricks at that tag available — pass it as `--git-ref` when adding
one later.

## CI

`tool/ci.sh` generates `p0g_app`, adds a service and two objectives (read and
write) to it, bootstraps it, and runs the generated workspace's analyzer, unit
and widget tests (including a service running in the CLI as a process place),
the CLI executable, and the web and Linux builds; the `rust` variant does the
same plus `cargo test`, and checks that the CLI executable loads the library
beside it and hashes with Rust. No e2e.

The generated app resolves the packages as an outside consumer does: from
`https://github.com/p0g-stack/p0g` at the candidate tag, through a local
mirror of `HEAD`, with `pub`, the analyzer, Mason and the `flutter_p0g`
launcher kept in scratch caches. CI runs it on every pull request.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
