# squadron_process: working agreements

Self-contained; no external base file.

- Extend Squadron, don't replace it. Anything Squadron already does (pools,
  cancellation, streams, exceptions, marshalling, codegen) is used as is.
- The patch stays minimal and upstreamable: a channel-factory hook, nothing
  app-specific.
- A place reports facts it has checked, never facts guessed from the platform.
- Nothing app-specific. Strategies and conventions belong in the bricks.
- Unofficial: the README says so; never imply Squadron's author endorses it.
- Pure Dart: no `package:flutter` import anywhere. `lib/squadron_process.dart`
  must compile for the VM, dart2js and dart2wasm; `dart:io` code lives behind
  `lib/io.dart` or conditional imports.
- Never depend on flutter_webui. Platforms plug in through `ProcessLauncher`
  and `EndpointStore`; the WebUI adapters live in the bricks.
- Pinned: Flutter 3.47.5 / Dart 3.13.4, Squadron 7.4.4 (`third_party/squadron/PIN`).
  Run `tool/squadron.sh` before `dart pub get`. A change to Squadron is a new
  or edited patch in `third_party/squadron/patches/` (git format-patch), with
  Squadron's own VM suite still passing.
- Tests the way Flutter tests platforms: unit tests against fakes
  (`PlaceLink.pair`, fake launchers and stores). The one real-process test
  runs `test/support/serve_main.dart`; no device or browser e2e here
  (that is devicelab).
- Facts keys change in the contracts table (p0g-stack reshape summary) first,
  then in `Fact`.
- The wire protocol is versioned (`Msg.version`); both ends come from the same
  app build, so bump it on any incompatible change rather than negotiating.
- Keep README and docs/webui-launch.md true to what the code does.
- Commit directly to main until a stable/parity release is declared.
