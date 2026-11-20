# Upstream packet: `Worker.channelFactory`

Status: branch pushed to the org fork, PR text ready. **No PR opened** (opening upstream PRs is not
authorized). The carried patch stays in the stack at
`squadron_process/third_party/squadron/patches/0001-Worker-pluggable-channel-factory.patch` and is unchanged.

| | |
| --- | --- |
| Upstream repository | https://github.com/d-markey/squadron |
| Base commit | `fd5becc4a480887aadc04b350b1fda844502065e` (`Rework tests`; upstream `main` tip and the pin in `squadron_process/third_party/squadron/PIN`, pubspec 7.4.5) |
| Fork | https://github.com/p0g-stack/squadron (created for this work) |
| Head branch | `worker-channel-factory` @ `493829dc13422466fa86496522fa4c7ffa0f7610` |
| Compare URL | https://github.com/d-markey/squadron/compare/fd5becc4a480887aadc04b350b1fda844502065e...p0g-stack:squadron:worker-channel-factory |
| Commits | one: `Worker: pluggable channel factory` |
| Diff | 7 files, +196 −8 |

## What the change does

`Worker.start()` always calls `Channel.open()`, so a worker can only run in an isolate (VM) or a Web Worker
(browser). `Channel` is already an interface, but the worker's channel is private and `Channel.open()` is not
injectable, so a custom `Channel` implementation has no way in.

- `ChannelFactory` typedef (`ExceptionManager`, `Logger?`, `EntryPoint`, start arguments → `Future<Channel>`).
- `Worker.channelFactory`, as a constructor parameter and as a settable field, documented as "must be set
  before the worker starts".
- `_openChannel` awaits the factory when set, otherwise `Channel.open()` exactly as before; the shared
  `_openChannel` future, stats start and `stop()` are unchanged.
- Exports `SquadronCancelationToken` and `StreamId`, which a `Channel` implementation needs for
  `cancelToken()` and `cancelStream()`.
- Tests: `test/13_channel_factory_suite.dart` (registered in both the VM and the browser suite):
  decorating `Channel.open()`, replacing the channel entirely (a channel with no platform thread behind it),
  one open for concurrent first requests, factory errors reaching the caller, and the default path.

## Behavioral checks actually executed

Dart 3.13.7, Chrome 157.0.8103.50 (for the browser runner).

1. `dart pub get` then `dart analyze` → `No issues found!`
2. `dart test -p vm test/squadron_vm_test.dart` → 694 passed, 5 skipped; the five new
   `CHANNEL FACTORY` tests pass in the VM runner.
3. Browser runner (needs `dart run tool/compile_tests.dart js` first, as for any browser run):
   `dart test -p chrome --compiler dart2js test/squadron_browser_test.dart` → 735 passed, 5 skipped; the five
   new tests pass there too.

## PR body

```text
Worker: pluggable channel factory

Worker.start() always calls Channel.open(), so a worker can only run in an
isolate (VM) or a Web Worker (browser). Channel is already an interface, but
the worker's channel is private and Channel.open() is not injectable, so a
custom Channel implementation has no way in.

Add ChannelFactory and Worker.channelFactory (constructor parameter and
settable field). When set, the first request awaits the factory instead of
Channel.open(); everything after it (stats, the shared _openChannel future,
stop()) is unchanged. With no factory, behavior is identical to before.

Export SquadronCancelationToken and StreamId, which a Channel implementation
needs for cancelToken() and cancelStream().

Tests: test/13_channel_factory_suite.dart, in both the VM and browser suites
(decorating Channel.open, replacing the channel, one open for concurrent
first requests, factory errors reaching the caller, the default path).
```

## Notes

- Base is the current upstream `main`, so the branch is directly PR-ready.
- No `p0g`-specific API is added: the factory signature follows the existing `Channel.open` parameters
  (`PlatformThreadHook` is deliberately not part of it, since a custom channel has no platform thread).
