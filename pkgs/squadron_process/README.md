# surfaces

The one workspace repo of the p0g GUI stack: a host-neutral Flutter API, one Rust
ops protocol, and the backends and CLI that put an app on every host.

Hosts: KernelSU WebUI (`ksu` bridge), WebUI X, plain web, AERA Recovery, Linux
desktop, Android. Every host feature is a capability with a fallback; apps check
capabilities, never host names.

## Scope

In:
- `surfaces`: the host-neutral API and `SurfaceScope`
- `surfaces_ui`: the shared design language
- `surfaces_webui`, `surfaces_aera`: the platform backends
- `surfaces-core`, `surfaces-ops`: the ops protocol, the `Handler` trait, jobs, the worker's main
- `tools/cli`: build, serve, sim, doctor
- `spec/`: the frozen contracts everything above implements

Out: anything app-specific (see `template-app`, `demo`), the AERA embedder
(`engine-aera`), graded host probes (`certify`).

## Proposed nest

```
spec/                 contracts first; code implements, fixtures prove
  protocol.md         Request/Envelope/JobStatus, error and state enums, limits, handshake
  capabilities.md     Cap id -> detection rule -> fallback; the one table
  effects.md          op effect classes (read/write/device), plan-confirm-execute, receipts
  core-abi.md         wasm alloc/free/call/bytes, packing, status byte
  layout.md           module layout, state dir ownership/mode, surfaces.yaml keys
  fixtures/           JSON cases run by both Rust and Dart tests
crates/
  surfaces-core/      protocol types + codec; no I/O
  surfaces-ops/       Handler, JobCtx, effect gates, worker main, in-process Runner
packages/
  surfaces/           API, SurfaceScope, fallback services; imports no backend
  surfaces_ui/        theme, widgets, capability/fallback presentation
  surfaces_webui/     ksu/webui/browser detection, worker transport, wasm core loader
  surfaces_aera/      AERA backend over engine-aera's system channel
tools/
  cli/                surfaces build|serve|sim|doctor
  e2e/                fake-host walks, run in CI
```

## Dependency direction

```
app dart  -> surfaces_webui | surfaces_aera -> surfaces
app rust  -> surfaces-ops -> surfaces-core
```

`surfaces` never imports a backend. `surfaces-core` does no I/O. One commit of
this repo pins both the Dart and the Rust half of an app; the handshake in
`spec/protocol.md` refuses a mismatch at startup.

## License

LGPL-3.0-or-later. Apps and their crates link without inheriting it.
