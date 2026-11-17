# Upstream packet: initialize the WASM module inside Web Workers

Status: branch pushed to the org fork, PR text ready. **No PR opened** (opening upstream PRs is not
authorized). The carried patch stays in the stack at `flutter_p0g/patches/frb/0003-web-worker-init.patch`
and is unchanged by this packet.

| | |
| --- | --- |
| Upstream repository | https://github.com/fzyzcjy/flutter_rust_bridge |
| Base commit | `1e4df906b6d0e96aefbfa40dde5fa2833d417c1a` (the stack's pin; 49 commits behind `master` `cf0e5064b0` when prepared) |
| Fork | https://github.com/p0g-stack/flutter_rust_bridge (created for this work) |
| Head branch | `web-worker-init` @ `9fa0e4630cbfb714e4ac7ce5949c9298a71a2acc` |
| Compare URL | https://github.com/fzyzcjy/flutter_rust_bridge/compare/1e4df906b6d0e96aefbfa40dde5fa2833d417c1a...p0g-stack:flutter_rust_bridge:web-worker-init |
| Commits | one: `web: initialize the WASM module inside Web Workers` |
| Diff | 2 files, +25 −15 |

Independent of the `--no-threads` packet above: it touches only the Dart web loader and needs no CLI change.

## What the change does

`initializeWasmModule` and the generated binding assume a page:

- the wasm-bindgen glue is loaded by appending a `<script>` element to `document.head`, which a dedicated
  worker does not have;
- the glue's global is published to and read from `window`, which is `undefined` in a worker;
- the init function is invoked through an extension-type member named `call`, which compiles to
  `Function.prototype.call(arg)`: the URL is passed as `this`, the init function receives no argument, and
  wasm-bindgen falls back to the URL of the current `<script>` — which a worker does not have.

The change loads the glue with `importScripts` when there is no `document` (resolved against the worker script
URL), publishes and reads the glue through `globalThis`, and calls the init function with
`callAsFunction(null, url)` so the `_bg.wasm` URL is actually passed. The page path is unchanged: same
`<script>` loading, same URL string.

Also drops the now-unused `_JSWasmBindgen` extension type and the `package:web` import in
`generalized_frb_rust_binding/_web.dart`.

## Behavioral checks actually executed

Tool versions: Dart 3.13.7, Chrome 157.0.8103.50 (headless), wasm-pack 0.15.1.

1. `cd frb_dart && dart analyze lib/src/wasm_module lib/src/generalized_frb_rust_binding test/wasm_module_web_test.dart`
   → `No issues found!` at both the base commit and the branch.
2. `dart test -p chrome test/wasm_module_web_test.dart test/consts_web_test.dart test/generalized_uint8list_web_test.dart`
   → 3 passed at both the base commit and the branch (no page-path regression).
3. Worker end-to-end (harness outside the repo, nothing committed): a Dart program importing
   `package:flutter_rust_bridge/src/wasm_module/_web.dart`, compiled with `dart compile js -O1`, loaded with
   `importScripts('worker.js')` in a dedicated Web Worker served over HTTP, next to a wasm-bindgen
   `no-modules` glue + `.wasm` pair produced by `build-web --no-threads`.
   - base `1e4df906`: the worker never loads the module; the failure surfaced from inside the worker is
     `TypeError: null: type 'JSNull' is not a subtype of type 'JSObject'` (`web.document.head!` on a null
     `document`).
   - branch: `initializeWasmModule(root: 'probe_wasm')` resolves, then the exported glue function
     `wasm_bindgen.add(2, 3)` returns `5`; the worker reports `RESULT ok sum=5 isWorker=true`.

## PR body

```text
web: initialize the WASM module inside Web Workers

`initializeWasmModule` and the generated binding assume a page:

- the wasm-bindgen glue is loaded with a <script> element appended to
  `document.head`, which does not exist in a dedicated worker;
- the glue's global is published and read through `window`, which is
  undefined in a worker;
- the init function is invoked through an extension type member named
  `call`, which compiles to `Function.prototype.call(arg)`: the URL is
  passed as `this`, the init function receives no argument, and
  wasm-bindgen falls back to the URL of the current <script>. A worker
  has none.

Load the glue with `importScripts` when there is no `document` (the path
resolves against the worker script URL), publish/read the glue through
`globalThis`, and call the init function with `callAsFunction(null, url)`
so the `_bg.wasm` URL is actually passed. Page behavior is unchanged: same
<script> loading, same URL.

Checks: `dart analyze` clean, the existing browser tests for the wasm
module / generalized uint8list pass, and the module now initializes inside a
dedicated Web Worker (a wasm-bindgen `no-modules` module reports its sum
back to the page) where it previously failed on a null `document`.
```

## Notes

- Branch base is the stack's pin; the two changed files are untouched between the pin and `master`'s tip at
  preparation time except for unrelated commits, so a rebase should be conflict-free.
- No regression test is included: exercising this needs a compiled wasm-bindgen module in a worker, which the
  package's unit tests do not have. If reviewers want one, the harness in check 3 is ~30 lines of Dart plus a
  page that starts the worker.
