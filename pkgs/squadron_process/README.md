# surfaces

What Flutter has no concept of: root, module storage, privileged jobs, and
what an operation is allowed to touch. One Rust `Handler`, one wire protocol,
one capability table; the same app code on KernelSU WebUI, WebUI X, plain web,
AERA Recovery, Linux and Android.

Lifecycle, back, insets, clipboard, theme are Flutter's; the embedders
(`flutter-aera`, `flutter-webui`) make them work per host. This repo starts
where those stop.

## Scope

In:
- `surfaces` (Dart): `Cap`, the ops client, `OpsTransport` interface, fallbacks
- `surfaces_ui` (Dart): shared design language
- `surfaces-core` (Rust): protocol types, the `Effect` enum, codec; no I/O
- `surfaces-ops` (Rust): `Handler`, `JobCtx`, effect gates, worker main, in-process `Runner`, backend selector
- `tools/cli`: build webui|aera|linux|android, serve fake hosts, doctor
- `example/`: one page per affordance; the integration test
- `spec/`: the frozen contracts

Out: embedders, app code, GPU code.

## Proposed nest

```
spec/
  protocol.md         Request/Envelope/JobStatus, error and state enums, limits, version handshake on every transport
  capabilities.md     Cap id -> detection rule -> fallback; the one table, generates the Dart constants
  effects.md          Effect::{Read, WriteAppData, WriteFs, Exec, Device}; plan-confirm-execute; receipts
  layout.md           module layout, state dir ownership/mode, surfaces.yaml keys
  fixtures/           JSON cases run by both Rust and Dart tests
crates/
  surfaces-core/
  surfaces-ops/
packages/
  surfaces/
  surfaces_ui/
tools/
  cli/
docs/
  hosts/              host reports exported from real devices by the example app; the support table is generated from them
example/
  lib/pages/          host, storage, files, ops, jobs, backends, core, ...
  rust/               as template-app; backends/ shows the swappable-backend pattern with harmless backends
  tool/e2e            drives every page under every fake host profile; fails on page errors
```

## Transports

| Host | Rust core | Ops |
|---|---|---|
| AERA, Linux, Android | flutter_rust_bridge, in-process | in-process `Runner` |
| WebUI, WebUI X | flutter_rust_bridge, sync web mode | root worker over `ksu.exec` (from `flutter-webui`) |
| plain web | flutter_rust_bridge, sync web mode | none; `Cap.ops` absent |

frb's sync web mode needs no cross-origin isolation. A spike proves its loader
inside the KernelSU and WebUI X webviews before `spec/protocol.md` is frozen;
if it fails, a hand-written wasm ABI returns as `spec/core-abi.md`.

## Dependency direction

```
app dart  -> flutter_webui -> surfaces
app rust  -> surfaces-ops -> surfaces-core
```

`surfaces` imports no embedder. `surfaces-core` does no I/O. One commit of
this repo pins both halves of an app; the handshake refuses a mismatch at
startup and `surfaces doctor` refuses it in CI.

## License

LGPL-3.0-or-later. Apps and their crates link without inheriting it.
