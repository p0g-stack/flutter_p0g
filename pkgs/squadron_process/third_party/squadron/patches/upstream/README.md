# Upstream proposals for Squadron

Status: **prepared, not sent.** Nothing goes upstream until squadron_process
has been tested standalone on its target platforms.

The series is two commits on
[d-markey/squadron](https://github.com/d-markey/squadron) commit
`fd5becc4a480887aadc04b350b1fda844502065e` (pubspec 7.4.5; upstream has no
tag for it). Each file is byte-identical to the patch squadron_process
applies (`../0001-...`, `../0002-...`; CI checks that they match). Apply in
order with `git am 0001-*.patch 0002-*.patch`. The two are independent
proposals; `0002` only shares the CHANGELOG "Unreleased" section with
`0001`.

## 0001: pluggable channel factory

`0001-Worker-pluggable-channel-factory.patch`. Rebased unchanged from
`v7.4.4` (`4ab7f15a`); only the CHANGELOG context moved under the 7.4.5
entry.

### Problem

`Worker.start()` always calls `Channel.open()`, so a worker runs in an
isolate on the VM or a Web Worker in a browser, and nowhere else. `Channel`
is already an interface, but the worker's channel is private and there is
no hook to supply another one. Running the same service in another process
(say, an elevated helper reached over a loopback socket) means forking
Squadron or re-implementing everything `Worker` does.

### Change

- `typedef ChannelFactory = Future<Channel> Function(ExceptionManager, Logger?, EntryPoint, List startArguments)`.
- `Worker.channelFactory`: a constructor parameter and a settable field.
  When set, `start()` awaits it instead of `Channel.open()`. Everything after
  that is unchanged: the shared `_openChannel` future (one open for
  concurrent first requests), stats, `stop()`.
- Export `SquadronCancelationToken` and `StreamId`, which a `Channel`
  implementation needs for `cancelToken()` and `cancelStream()`.
- CHANGELOG entry under "Unreleased".

With no factory set, behavior is identical. No existing API changes. A
factory's error reaches the caller the same way a failing `Channel.open()`
does.

### Tests

`test/13_channel_factory_suite.dart`, in Squadron's `TestContext` style and
registered in both `squadron_vm_test.dart` and `squadron_browser_test.dart`:

- a factory that wraps `Channel.open()` works end to end;
- a factory that returns a different `Channel` replaces the platform one;
- concurrent first requests open the channel once;
- a factory error fails the request;
- no factory gives Squadron's own channel.

Run against the `v7.4.4` tree on 2026-10-01: VM suite 694 passed, browser
suite (Chrome, dart2js and dart2wasm, JS and Wasm workers) 2940 passed.
Existing analyzer infos in Squadron are unchanged; the patch adds none.
Not yet rerun on the 7.4.5 tree.

### Why it is worth having upstream

The hook is small and generic: any transport that can carry Squadron's
request/response lists (a socket, a native port, a test double) becomes a
place a worker can run, without Squadron knowing about it. squadron_process
is one user; in-memory channels for unit tests are another.

## 0002: expose the Wasm worker's script URL

`0002-web-expose-worker-script-url.patch`.

### Problem

A Web Assembly worker starts from a blob URL holding Squadron's loader
script (`EntryPointUri._wasmLoaderScript` in
`lib/src/_impl/web/_entry_point_uri.dart`). Inside that worker
`self.location` is the blob, so code that loads files next to the worker
(a wasm-bindgen module, for instance) has no base URL and can only guess
from the origin, which is wrong whenever the app is not served from the
origin root.

### Change

The loader already derives the absolute URL of the worker's `.wasm` file
(`workerUri`). One line assigns it to `globalThis.squadronWorkerScriptUrl`
immediately after that, before the Dart runtime is imported or `main` is
invoked. `self.location`, the blob, worker packaging and the channel
protocol are unchanged. JavaScript workers run from their own URL and are
not touched. CHANGELOG entry under "Unreleased".

### Tests

None in Squadron's suite yet: checking the value needs a Wasm test worker
that reports it, i.e. a new service method and rebuilt worker binaries.
Until then it is checked by the consuming app's blob-worker qualification.

### Why it is worth having upstream

It is the only place that knows the worker's real URL, and the global is
inert for code that ignores it.
