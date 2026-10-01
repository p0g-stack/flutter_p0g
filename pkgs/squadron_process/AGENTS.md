# squadron_process: working agreements

Self-contained; no external base file.

- Extend Squadron, don't replace it. Anything Squadron already does (pools,
  cancellation, streams, exceptions, marshalling, codegen) is used as is.
- The patch stays minimal and upstreamable: a channel-factory hook, nothing
  app-specific.
- A legitimate, generic third-party package (Yuv, 2026-10-01): nothing
  specific to one app, platform embedding or project (no WebUI, no p0g, no
  root assumptions). Facts are a neutral map supplied by the app's
  `FactsCheck`; the package defines no keys and makes no checks. Lifetime
  defaults must make sense for any client/helper pair.
- A place reports facts it has checked, never facts guessed from the platform.
- Launchers are siblings behind `ProcessLauncher`: plain, one per OS elevation
  front-end, and whatever an embedding brings. Picking a launcher by OS is
  fine; facts are not derived from the OS.
- Unofficial: the README says so; never imply Squadron's author endorses it.
- Pure Dart: no `package:flutter` import anywhere. `lib/squadron_process.dart`
  must compile for the VM, dart2js and dart2wasm; `dart:io` code lives behind
  `lib/io.dart` or conditional imports.
- No dependency on any embedding (flutter_webui included). Embeddings plug in
  through `ProcessLauncher`, `EndpointStore` and `FactsCheck`.
- Pinned: Flutter 3.47.5 / Dart 3.13.4, Squadron 7.4.4 (`third_party/squadron/PIN`).
  Run `tool/squadron.sh` before `dart pub get`. A change to Squadron is a new
  or edited patch in `third_party/squadron/patches/` (git format-patch), with
  Squadron's own VM suite still passing.
- Tests the way Flutter tests platforms: unit tests against fakes
  (`PlaceLink.pair`, fake launchers and stores). The one real-process test
  runs `test/support/serve_main.dart`; no device or browser e2e here
  (that is devicelab).
- The wire protocol is versioned (`Msg.version`); both ends come from the same
  app build, so bump it on any incompatible change rather than negotiating.
- Keep README and docs/launchers.md true to what the code does.
- Commit directly to main until a stable/parity release is declared.
- Stable surface (used by bricks since 2026-10-01): `serve(Map<String, Invoker>,
  args, facts:)`, `ProcessPlace(launcher:, store:, command:)` and
  `place.bind(worker, service:)`, plus the serve CLI options and ready-line
  JSON in docs/serve.md. Change them only additively; anything else bumps the
  minor version and is announced to consumers first.
