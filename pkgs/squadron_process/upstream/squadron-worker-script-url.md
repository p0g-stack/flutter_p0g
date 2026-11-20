# Upstream packet: expose the Wasm worker's script URL

Status: branch pushed to the org fork, PR text ready. **No PR opened** (opening upstream PRs is not
authorized). The carried patch stays in the stack at
`squadron_process/third_party/squadron/patches/0002-web-expose-worker-script-url.patch` and is unchanged; the
branch additionally contains a regression test that the patch does not carry.

| | |
| --- | --- |
| Upstream repository | https://github.com/d-markey/squadron |
| Base commit | `fd5becc4a480887aadc04b350b1fda844502065e` (`Rework tests`; upstream `main` tip and the pin in `squadron_process/third_party/squadron/PIN`, pubspec 7.4.5) |
| Fork | https://github.com/p0g-stack/squadron (created for this work) |
| Head branch | `web-worker-script-url` @ `915a6517811cc643756d6fbf4890de99478ceb25` |
| Compare URL | https://github.com/d-markey/squadron/compare/fd5becc4a480887aadc04b350b1fda844502065e...p0g-stack:squadron:web-worker-script-url |
| Commits | one: `Web: expose the Wasm worker's script URL` |
| Diff | 3 files, +48 −0 |

Independent of the channel-factory packet: the branch is cut from `fd5becc` alone, and its `CHANGELOG` entry
sits in its own `## Unreleased` section.

## What the change does

A Web Assembly worker runs from a blob URL that holds Squadron's loader script, so inside the worker
`self.location` is the blob, not the worker's files. Code in the worker that loads sibling assets (a
wasm-bindgen module next to the worker, for instance) has no reliable base URL and ends up guessing from the
origin.

The loader already derives the absolute URL of the worker's `.wasm` file (`workerUri`). The change assigns it
to `globalThis.squadronWorkerScriptUrl` right after deriving it — before the Dart runtime is imported or
`main` is invoked — so the worker can resolve relative paths against its real location. `self.location`, the
blob, the worker packaging and the channel protocol are unchanged. JavaScript workers are unaffected: they run
from their own URL.

## Behavioral checks actually executed

Dart 3.13.7, Chrome 157.0.8103.50.

1. `dart pub get`, `dart analyze` → `No issues found!`
2. `dart test -p vm` → 689 passed, 5 skipped.
3. Browser runner as documented in `tool/run_tests.sh` (`dart run tool/compile_tests.dart js wasm` first, so
   the JS and WASM workers exist): `dart test -p chrome --compiler dart2js` → 1462 passed, 10 skipped. This
   includes the JS runner *and* the WASM runner suites, i.e. real Wasm workers still load through the changed
   loader.
4. New test `test/web_worker_script_url_test.dart` (browser-only): reads the blob's loader script through
   `fetch` and asserts that `globalThis.squadronWorkerScriptUrl=workerUri;` appears after
   `const workerUri=` and before `let newRt=`; also asserts a `.js` entry point keeps its own URL.
   Passes on the branch, fails at the base commit (`git switch fd5becc` with the test file present →
   `wasm worker loader exposes the worker script url` fails), which is what makes it a regression test.

## PR body

```text
Web: expose the Wasm worker's script URL

A Web Assembly worker runs from a blob URL that holds Squadron's loader
script, so inside the worker self.location is the blob, not the worker's
files. Code in the worker that loads sibling assets (a wasm-bindgen module
next to the worker, for instance) has no reliable base URL and ends up
guessing from the origin.

The loader already derives the absolute URL of the worker's .wasm file
(workerUri). Assign it to globalThis.squadronWorkerScriptUrl right after
deriving it, before the Dart runtime is imported or main is invoked, so the
worker can resolve relative paths against its real location. self.location,
the blob, the worker packaging and the channel protocol are unchanged.
JavaScript workers do not need it: they run from their own URL.

Tests: test/web_worker_script_url_test.dart reads the loader script of a
Wasm-worker entry point and checks the global is set before the runtime is
imported; it fails without the change. The VM and Chrome suites (including
the WASM workers) pass.
```

## Notes

- Base is the current upstream `main`, so the branch is directly PR-ready.
- The global is deliberately unnamespaced inside the worker (no module system there); the name matches the
  loader's existing `workerUri` derivation.
