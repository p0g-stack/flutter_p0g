# Upstream proposal: pluggable channel factory for Squadron

Status: **prepared, not sent.** Nothing goes upstream until squadron_process
has been tested standalone on its target platforms.

`0001-Worker-pluggable-channel-factory.patch` is one commit on
[d-markey/squadron](https://github.com/d-markey/squadron) `v7.4.4`
(`4ab7f15a`). It is byte-identical to the patch squadron_process applies
(`../0001-...`; CI checks that the two match). Apply with
`git am 0001-Worker-pluggable-channel-factory.patch`.

## Problem

`Worker.start()` always calls `Channel.open()`, so a worker runs in an
isolate on the VM or a Web Worker in a browser, and nowhere else. `Channel`
is already an interface, but the worker's channel is private and there is
no hook to supply another one. Running the same service in another process
(say, an elevated helper reached over a loopback socket) means forking
Squadron or re-implementing everything `Worker` does.

## Change

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

## Tests

`test/13_channel_factory_suite.dart`, in Squadron's `TestContext` style and
registered in both `squadron_vm_test.dart` and `squadron_browser_test.dart`:

- a factory that wraps `Channel.open()` works end to end;
- a factory that returns a different `Channel` replaces the platform one;
- concurrent first requests open the channel once;
- a factory error fails the request;
- no factory gives Squadron's own channel.

Run against the patched tree on 2026-10-01: VM suite 694 passed, browser
suite (Chrome, dart2js and dart2wasm, JS and Wasm workers) 2940 passed.
Existing analyzer infos in Squadron are unchanged; the patch adds none.

## Why it is worth having upstream

The hook is small and generic: any transport that can carry Squadron's
request/response lists (a socket, a native port, a test double) becomes a
place a worker can run, without Squadron knowing about it. squadron_process
is one user; in-memory channels for unit tests are another.
