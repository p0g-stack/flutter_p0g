# Web runtime proofs

These are opt-in, browser-backed qualification fixtures, separate from the
in-memory `flutter test` suite. They do not use a demo/flasher app, attached
devices, deployment credentials, COOP/COEP, JSPI or threaded Rust wasm.

Prerequisites: the repository's pinned Flutter SDK on PATH, Node 24, Rust stable
with `wasm32-unknown-unknown`, cargo-expand, wasm-pack and wasm-bindgen-cli.
From the repository root:

```sh
flutter pub get
(cd pkgs/flutter_p0g_tool/tool/web_runtime_proof && npm ci && PLAYWRIGHT_SKIP_BROWSER_GC=1 npx playwright install chromium)
bash pkgs/flutter_p0g_tool/tool/web_runtime_proof/run.sh all
```

Use `frb` or `defines` instead of `all` to run just one proof. Each run prints a
fresh temporary directory containing compiler logs, generated bindings, build
outputs and the browser JSON evidence. Keep this directory when investigating a
failure. No SDK cache is overwritten. `CHROMIUM_EXECUTABLE` can select an existing
supported Chromium. `FRB_SOURCE` may select an already patched source checkout;
the runner checks its pinned HEAD and reverse-applicability of both patches.
`FRB_CODEGEN` may select a codegen binary already built from that exact source.
Without these overrides it fetches the pinned upstream source, applies the
series and builds codegen itself.

## Standalone FRB worker initialization

A five-line real Rust API computes `rust:5050`. The runner generates the Dart
bindings with the patched codegen, builds Rust with `build-web --no-threads
--release`, then compiles the Dart caller to JavaScript.
Playwright launches a **dedicated classic worker**, not a page or a module
worker. That worker must initialize FRB and return the exact Rust result,
`hasDocument: false`, and `isolated: false`. Browser errors and serialized
initialization exceptions fail the proof. The fixture server deliberately sends
neither COOP nor COEP headers; the harness also checks their absence.

## Resolved define parity

A minimal Flutter page and dedicated Dart worker call the same service function:
`String.fromEnvironment('P0G_WORKER_VALUE')` and
`bool.fromEnvironment('P0G_WORKER_FLAG')`. Its worker filenames follow Squadron's
artifact convention without needing Squadron code generation or its transport.
The runner invokes the real local `flutter_p0g build web` command four times:
JS/wasm × explicit flags/JSON define file. The command, not this fixture, invokes
`compileWorkers`. Every page and worker must return the identical object with
`a=b with spaces 日本語` and `true`. The wasm case actually instantiates and runs
the Dart wasm worker, rather than loading its JS alternative. All four outputs
are served below `/proof/`.

The unit tests additionally check the exact compiler argv (one item per define,
including duplicate keys, ordering, equals signs, whitespace and Unicode) and
WebUI's real parser plus a parser fixture without `pwa-strategy`.
