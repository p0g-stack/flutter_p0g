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
