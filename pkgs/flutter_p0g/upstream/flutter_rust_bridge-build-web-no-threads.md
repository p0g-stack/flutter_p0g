# Upstream packet: `build-web --no-threads` (single-threaded WASM on stable)

Status: branch pushed to the org fork, PR text ready. **No PR opened** (opening upstream PRs is not
authorized). The carried patch stays in the stack at `flutter_p0g/patches/frb/0001-build-web-no-threads.patch`
and is unchanged by this packet.

| | |
| --- | --- |
| Upstream repository | https://github.com/fzyzcjy/flutter_rust_bridge |
| Base commit | `1e4df906b6d0e96aefbfa40dde5fa2833d417c1a` (the stack's pin; 49 commits behind `master` `cf0e5064b0` when prepared) |
| Fork | https://github.com/p0g-stack/flutter_rust_bridge (created for this work) |
| Head branch | `web-build-no-threads` @ `315e93a235871edfa65a5fd10edf7a8040952efb` |
| Compare URL | https://github.com/fzyzcjy/flutter_rust_bridge/compare/1e4df906b6d0e96aefbfa40dde5fa2833d417c1a...p0g-stack:flutter_rust_bridge:web-build-no-threads |
| Commits | one: `build-web: add --no-threads for single-threaded WASM builds` |
| Diff | 8 files, +180 −8 |

Tool versions used for the checks: Dart 3.13.7, rustc/cargo 1.99.0, wasm-pack 0.15.1, wasm-bindgen 0.2.128.

## What the change does

`build-web` always produces multi-threaded WASM: nightly toolchain, `-Z build-std=std,panic_abort`, and
atomics/shared-memory rustflags. Such a module needs cross-origin isolation (COOP/COEP). The manual already
documents a main-thread-only mode (`default_dart_async: false`), but the CLI cannot build for it, and the
crate does not compile with the `thread-pool` feature disabled on wasm because the generated default handler
uses a thread-local pool that has no `BaseThreadPool` implementation in that configuration.

- `frb_dart` build-web CLI: new `--threads` flag (default `true`, so nothing changes by default). With
  `--no-threads` the wasm-pack invocation drops `-Z build-std`, leaves `RUSTUP_TOOLCHAIN` unset unless the
  user passes `--wasm-pack-rustup-toolchain`, and passes no rustflags (`CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS`
  is only set when the user supplies `--wasm-pack-rustflags`). `WasmPackRustflagsResolution.rustflags` is
  nullable to express "leave cargo's own configuration alone".
- `frb_rust`: `BaseThreadPool` is implemented for `&'static LocalKey<SimpleThreadPool>` in the no-thread-pool
  stub, which is what the generated web default handler instantiates.
- `frb_rust`: without `thread-pool`, `Handler::wrap_normal` becomes a documented compile-time error that names
  the fix (`#[frb(sync)]`, `async fn`, or `default_dart_async: false`) instead of failing somewhere else.
- docs: the cross-origin page lists the three steps (disable `thread-pool`, `default_dart_async: false`,
  `build-web --no-threads`).

## Behavioral checks actually executed

1. `cd frb_dart && dart analyze lib/src/cli test/build_web_executor_test.dart test/entrypoint_test.dart test/build_web_entrypoint_test.dart`
   → `No issues found!`
2. `dart test test/build_web_executor_test.dart test/entrypoint_test.dart test/build_web_entrypoint_test.dart`
   → 24 tests passed (includes the two new tests: rustflags resolution with `threads: false`, and
   `executeBuildWeb(threads: false)` asserting the wasm-pack argv has no `-Z`/`build-std` and the env has no
   `RUSTUP_TOOLCHAIN`/`CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS`).
3. `cargo test -p flutter_rust_bridge --lib` (default features) → 98 passed;
   `cargo test -p flutter_rust_bridge --lib --no-default-features --features anyhow,dart-opaque,log,portable-atomic,rust-async,user-utils,wasm-start`
   → 98 passed, including the new `thread_pool::stub::tests::web_default_handler_pool_type_is_a_thread_pool`.
4. `cargo check -p flutter_rust_bridge --target wasm32-unknown-unknown --no-default-features --features <same>`
   → `Finished`; 5 warnings, the same five as at the base commit (unused imports / unused `Transfer`).
5. Generated-default-handler probe (a scratch crate depending on the local `frb_rust` with `thread-pool`
   disabled, calling `frb_generated_default_handler!()`):
   - base `1e4df906`: 6 × `error[E0277]: the trait bound &LocalKey<SimpleThreadPool>: BaseThreadPool is not satisfied`
     (and with a plain function also `error[E0599]: no method named wrap_normal`);
   - branch: builds; adding a plain (non-`sync`, non-`async`) function fails with
     `error[E0080]: evaluation panicked: flutter_rust_bridge: a plain (non-async, non-sync) function needs the thread-pool feature...`.
6. CLI end-to-end on a minimal wasm-bindgen cdylib crate:
   `dart run bin/flutter_rust_bridge.dart build-web -c <crate> -o web --release --no-threads --verbose`
   → `wasm-pack build -t no-modules -d web/pkg --no-typescript --out-name probe_wasm <crate> --` with env
   `{removedParentEnvKeys: RUSTFLAGS,CARGO_ENCODED_RUSTFLAGS}` only, built on the stable toolchain (rustc 1.99.0),
   producing `probe_wasm.js` + `probe_wasm_bg.wasm`. The default (threads) invocation on the same crate is
   byte-identical to the base commit: `-Z build-std=std,panic_abort`, `RUSTUP_TOOLCHAIN=nightly` and the ten
   shared-memory rustflags.

Note on the generated file: `frb_dart/lib/src/cli/build_web/entrypoint.g.dart` is produced by `build_cli`,
which `frb_dart/pubspec.yaml` currently comments out (`kevmoo/build_cli#168`). The added block follows the
generator's formatting for long flags (compare `wasm-pack-rustup-toolchain` and `skip-tool-install`), and the
generated parser is covered by check 2 (`--no-threads` maps to `threads: false`).

## PR body

```text
build-web: add --no-threads for single-threaded WASM builds

`build-web` always builds multi-threaded WASM: it forces the nightly
toolchain, passes `-Z build-std=std,panic_abort` and sets atomics /
shared-memory rustflags. The output needs cross-origin isolation
(COOP/COEP), which many hosts cannot provide. The manual already describes
a main-thread-only mode (`default_dart_async: false`), but the CLI gives no
way to build for it, and the crate does not compile without the
`thread-pool` feature on wasm.

- build-web: add `--threads` (default true). With `--no-threads` it skips
  `-Z build-std`, leaves RUSTUP_TOOLCHAIN unset unless
  `--wasm-pack-rustup-toolchain` is given, and passes only a user-supplied
  `--wasm-pack-rustflags`. Stable Rust is enough.
- frb_rust: implement `BaseThreadPool` for the thread-local pool the
  generated web default handler uses, so the crate compiles with
  `thread-pool` disabled.
- frb_rust: without `thread-pool`, `Handler::wrap_normal` is a compile-time
  error naming the fix (`#[frb(sync)]`, `async fn` or
  `default_dart_async: false`) instead of failing later.
- docs: describe the three steps on the cross-origin page.

Default behavior (threads on) is unchanged.

Checks: `dart analyze` and the build-web CLI tests (24 passed), `cargo test
-p flutter_rust_bridge --lib` with and without `thread-pool` (98 passed
each), `cargo check --target wasm32-unknown-unknown` without `thread-pool`,
a build of a scratch crate using `frb_generated_default_handler!()` (fails
at 1e4df906, builds here; a plain function reports E0080), and a real
`build-web --no-threads` run on stable Rust producing a loadable module.
```

## Notes

- Branch base is the stack's pin (`1e4df906`), 49 commits behind `master` `cf0e5064b0`, but none of those
  commits touch the files this branch changes (checked with `git log <pin>..master -- <paths>`), so the GitHub
  PR diff against `master` is exactly this change and a rebase is conflict-free.
- `frb_dart` `entrypoint.g.dart` will need regenerating if `build_cli` is re-enabled upstream.
