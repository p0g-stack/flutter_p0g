# bricks

> This repo was `template-app`; it is being renamed to `bricks`.

[Mason](https://pub.dev/packages/mason) bricks for p0g-stack apps. Platform
folders are not here: `flutterp0g_tool create .` adds `webui/` and `aera/` to
any Flutter app, the way `flutter create --platforms` does.

## Bricks

| Brick | Stamps |
|---|---|
| `p0g_app` | a pub workspace: `core/` (pure Dart, the logic), `app/` (Flutter GUI on core), `cli/` (Dart CLI on core, `dart compile exe`; also the WebUI root process in serve mode), optional `rust/` via frb for crates the core uses; Squadron + `squadron_process`; logging convention |
| `service` | a Squadron service exposed to both the GUI and the CLI |
| `strategy` | a strategy with `available(facts)` (e.g. on-device `dd` vs host `fastboot fetch`) |

A new app: `mason make p0g_app`, then `flutterp0g_tool create .`, write the
core, then `flutterp0g_tool build webui` / `aera`.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
