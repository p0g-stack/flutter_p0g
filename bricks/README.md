# template-app

The bare surfaces app. It builds on every target and is what new apps are
stamped from.

Targets: KernelSU WebUI / WebUI X module, plain web, AERA `.aerap`, Linux,
Android. Same `lib/` and `rust/` for all of them.

## Scope

In: the minimal Dart entry, a `rust/` workspace with core, worker and the
flutter_rust_bridge crate, one `surfaces.yaml`, CI that builds every target,
`docs/` sketches of the patterns a stamped app will need.

Out: features. One example op and one example job, nothing more. Anything
reusable moves to `surfaces`; anything illustrative moves to `surfaces/example`.

## Proposed nest

```
surfaces.yaml         single source: id, name, version, worker, rust dirs; generates the Dart constants
lib/
  main.dart           WebUiBinding on webui targets, stock binding elsewhere; one page
  native/             loads the frb crate on dart:io; frb sync web mode on web
rust/
  Cargo.toml          workspace; surfaces-core/-ops pinned by rev
  core/               app logic + Handler; every op declares its Effect
  worker/             fn main() { surfaces_ops::worker::main(AppOps) }
  native/             frb crate
bootstrap/            from flutter-webui; index.html host hooks
android/ linux/       flutter create output, pruned
docs/
  backends.md         the swappable-backend sketch: trait, available(), preference order, tiers
.github/workflows/    ci: analyze, test, codegen check, build all targets, e2e; release
```

## Rules

- `surfaces.yaml` is the only place the app id lives.
- Dart and Rust pin the same `surfaces` commit; `surfaces doctor` and the
  startup handshake both check it.
- `rust_builder` and generated frb code are produced by the CLI, not vendored
  per app.
- The template's example ops are `Effect::Read`, so a stamped app starts safe.

## Stamping an app

Keep this layout; add only under `lib/`, `rust/core` and `rust/worker`. App
backends live behind a trait in `rust/core` and depend only on
`surfaces-core` and `surfaces-ops`; `docs/backends.md` shows the shape,
including a host-provided transport (USB via `nusb` natively, WebUSB from Dart
on the web) under a host-neutral protocol.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
Apps may link this library statically or dynamically, private apps included,
without releasing their own code or shipping relinking material. Changes to
the library itself stay LGPL.
