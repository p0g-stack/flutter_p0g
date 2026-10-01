# squadron_process

> **Unofficial.** This package is not part of Squadron and is not affiliated
> with or endorsed by Squadron's author. It needs a small patch to Squadron
> (see [Squadron patch](#squadron-patch)) until an equivalent hook exists
> upstream.

An unofficial extension for [Squadron](https://pub.dev/packages/squadron) that
adds a third place to run a worker. Squadron runs a service in an **isolate**
(native) or a **Web Worker** (web). This package adds **another process**,
optionally elevated, reached over a loopback WebSocket:

| Place | Where | For example |
|---|---|---|
| isolate | in-process (Squadron) | most work on desktop and mobile |
| web worker | Web Worker (Squadron) | most work on the web |
| process | the app's own Dart CLI in serve mode, hosting the same Squadron service | work that needs other rights than the UI has: an elevated helper for a disk writer or installer (the balenaEtcher pattern), a root helper behind a web UI on a rooted phone |

The same service class runs in all three; only the channel differs.

Features:

- Bind any generated Squadron worker to a place; requests, streams,
  cancellation and Squadron exceptions work unchanged.
- One CLI process serves several named services.
- Launchers: plain, and per-OS elevation (`pkexec`, `su`, the macOS admin
  prompt, UAC), or your own.
- A token handshake that also carries the facts the host checked.
- Lifetime: the host lingers for a grace window after its last client and
  then cancels its work and exits.
- Client library runs on the Dart VM, dart2js and dart2wasm; the host needs
  `dart:io`.

Status: 0.1.0, unpublished. A service runs in a separate CLI process end to
end, including through stand-in `su` / `pkexec` / `osascript` front-ends (VM
tests). The client library compiles for dart2js and dart2wasm; its codec and
facts tests pass in Chromium. The real elevation prompts have not been run
here.

## Install

```yaml
dependencies:
  squadron_process:
    git:
      url: https://github.com/p0g-stack/squadron_process
      ref: <commit sha>
```

Then, from the package or pub workspace root:

```sh
dart pub get
dart run squadron_process:squadron_patch   # patched Squadron + dependency_overrides
dart pub get
```

A runnable example is in [example/](example/squadron_process_example.dart).

## Use

Bind a worker to a place before its first request. The worker class is the one
squadron_builder generated; nothing in the service changes.

```dart
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';

final place = ProcessPlace(
  launcher: ElevatedLauncher.forHost()!,         // pkexec / su / macOS admin / UAC
  store: FileEndpointStore(sessionPath),          // finds a running host; needed when stdout is hidden
  command: ProcessCommand(cliPath, arguments: ['serve', '--session-file', sessionPath]),
);
final worker = place.bind(MyServiceWorker(), service: 'my');
final facts = await place.facts();                // checked by the helper process
if (facts.has('raw_disk')) { ... }

final local = LocalPlace(check: checkMyFacts).bind(MyServiceWorker());
```

```dart
// The app's CLI: the same service, hosted for the process place.
import 'dart:io';
import 'package:squadron_process/io.dart';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'serve') {
    exit(await serve({'my': MyServiceWorker()}, args.skip(1).toList(), facts: checkMyFacts));
  }
}
```

`serve` hosts every named service in the one CLI process (each generated
worker in its own isolate) and forwards each client link to the service it
names. Values crossing the link use a
small binary codec with the value types of Flutter's `StandardMessageCodec`;
custom types need Squadron marshalers, exactly as for Web Workers.

## Places

| Kind | Class | Facts from |
|---|---|---|
| `isolate` / `web_worker` | `LocalPlace` | its `check`, run in the current context |
| `process` | `ProcessPlace` | the host's `facts` check, run in the host and sent in the handshake |

A process-place call costs a few hundred microseconds on loopback, and bulk
streams move about 110 MiB/s; an isolate is roughly ten times faster on both.
Numbers and method: [doc/benchmark.md](doc/benchmark.md).

## Facts

Platform hints (`kIsWeb`, `Platform.isX`) say what the OS is, not what this
place may do: an unprivileged UI and the elevated helper it started run on the
same machine and can do different things. Each place reports facts it checked
itself. squadron_process carries them as a neutral map (`PlaceFacts`) and
defines no keys: the app's `FactsCheck` decides what to check and what to call
it. Absent reads as false.

## Lifetime

The host keeps running while any client link is open, idle or not. When the
last link closes it waits a grace window (default 10 s, `--grace-ms`) for a
client to come back, for instance a restarted UI; tasks keep running
meanwhile and their results for the old link are dropped. If no client returns,
it cancels every running task and exits. A host nobody connects to exits after
`--first-link-grace-ms` (default 30 s). SIGTERM and SIGINT do the same as an
expired window.

A worker outlives its link. If the link drops, calls in flight on it fail with
a `WorkerException`; the worker's next call opens a new link, finding the host
again and starting a new one if the old host is gone. Workers that lose a host
together start one new host between them. In-flight calls are not replayed:
on loopback a dropped link almost always means the host itself went away.

One host serves any number of clients at once, each on its own link, with
its own requests, cancellations and streams.

## Launchers

`ProcessLauncher` implementations are siblings: `IoProcessLauncher` (the
caller's rights) and one per OS elevation front-end, `PkexecLauncher`,
`SuLauncher`, `MacAdminLauncher` and `WindowsRunAsLauncher`
(`ElevatedLauncher.forHost()` picks one). An embedding with its own way of
starting processes implements the same interface. Requirements, discovery
through `--launch-id` and the session file, and security notes:
[doc/launchers.md](doc/launchers.md).

## Squadron patch

`Worker.start()` only opens Squadron's own channels. The patch adds
`Worker.channelFactory` (constructor parameter and settable field) and exports
`SquadronCancelationToken` and `StreamId`, which a `Channel` implementation
needs. It lives in `third_party/squadron/patches/` against the release pinned
in `third_party/squadron/PIN` (7.4.4, 4ab7f15) and is meant to go upstream once
it has been used standalone; Squadron's own VM suite passes with it applied.

```sh
tool/squadron.sh    # patched tree in third_party/squadron/src + pubspec_overrides.yaml
dart test           # VM
dart test -p chrome test/codec_test.dart test/facts_test.dart
```

Until the patch is upstream, an app depending on squadron_process needs the
same patched Squadron: `dart run squadron_process:squadron_patch` from its
package or workspace root fetches it into `.dart_tool` and adds the
`dependency_overrides` entry. How a CLI wires `serve`, its options and its
output: [doc/serve.md](doc/serve.md).

## Limitations

- Needs the Squadron patch until upstream has a channel hook.
- Values crossing the link are limited to the codec's types (those of Flutter's
  `StandardMessageCodec`); custom types need Squadron marshalers.
- The host trusts any local client that presents the token; there is no peer
  credential check.
- The default link is a loopback WebSocket. Browsers with Local Network Access
  may block it for pages from other origins; a custom `PlaceLink` is the way
  around it ([doc/transport.md](doc/transport.md)).
- Calls in flight when a link drops fail; they are not resumed on the next
  link, even when the host kept them running through its grace window.

## Scope

In: the process channel (client and serve host), the launcher interface with
plain and OS-elevation launchers, place facts as a neutral map, the Squadron
patch.

Out: what facts to check and how to act on them, and any one embedding's own
launcher; those belong to the app or its kit.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
Apps may link this library statically or dynamically, private apps included,
without releasing their own code or shipping relinking material. Changes to
the library itself stay LGPL.
