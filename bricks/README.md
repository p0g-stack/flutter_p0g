# template-app

The bare surfaces app. It builds on every target and is what new apps
(`app-cbm` first) are stamped from.

## Scope

In: the minimal Dart entry with `SurfaceScope` wired in, a `rust/` workspace
with core, worker and the flutter_rust_bridge crate, one `surfaces.yaml`, CI
that builds every target.

Out: features. One example op and one example job, nothing more. Anything
reusable moves to `surfaces`; anything illustrative moves to `demo`.

## Proposed nest

```
surfaces.yaml         single source: id, name, version, worker, core, rust dirs
lib/
  main.dart           Surface.init with the backends; SurfaceScope; one page
  native/             loads the frb crate on dart:io; identity on web
rust/
  Cargo.toml          workspace; surfaces-core/-ops pinned by rev
  core/               app logic + Handler; also built to core.wasm
  worker/             fn main() { surfaces_ops::worker::main(AppOps) }
  native/             frb cdylib; the fixed shim set only
web/                  index.html host hooks
webui/                module.prop, customize.sh, config.json templates
android/ linux/       flutter create output, pruned
.github/workflows/    ci: analyze, test, codegen check, build all targets, e2e; release
```

## Rules

- `surfaces.yaml` generates the Dart constants; an id mismatch fails the build.
- Dart and Rust pin the same `surfaces` commit; `surfaces doctor` and startup
  handshake both check it.
- `rust_builder` and generated frb code are produced by the CLI, not vendored
  per app.

## Stamping an app

An app keeps this layout and adds only to `lib/`, `rust/core` and
`rust/worker`. App backends (CBM's fastboot and dd) live behind a trait in
`rust/core` and depend only on `surfaces-core` and `surfaces-ops`.

## License

LGPL-3.0-or-later.
