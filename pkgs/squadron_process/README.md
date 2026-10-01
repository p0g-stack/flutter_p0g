# squadron_process

> Formerly `surfaces`. Its Rust crates, transports, CLI, templates and design
> package are gone: their jobs moved to Squadron, the Mason bricks (`bricks`),
> `flutter_p0g` and app code.

An unofficial extension for [Squadron](https://pub.dev/packages/squadron) that
adds a third place to run a worker. Squadron runs a service in an **isolate**
(native) or a **Web Worker** (web). This package adds **another process**,
optionally elevated, reached over a socket:

| Place | Where | Used for |
|---|---|---|
| isolate | in-process (Squadron) | AERA (already root), tests |
| web worker | Web Worker (Squadron) | plain web |
| process | the app's own Dart CLI in serve mode, hosting the same Squadron service | WebUI root work (started through flutter-webui's root channel); later desktop via `pkexec` |

The same service class runs in all three; only the channel differs.

Status: 0.1.0, unpublished. The process place runs a Squadron service in a
separate Dart CLI process over a loopback WebSocket end to end (VM tests); the
client side compiles and its codec and facts tests pass under dart2js and
dart2wasm in Chromium. Not yet run inside a manager WebView.

## Use

Bind a worker to a place before its first request. The worker class is the
one squadron_builder generated; nothing in the service changes.

```dart
import 'package:squadron_process/squadron_process.dart';

// In the page: the app's root process, started through a launcher.
final place = ProcessPlace(
  launcher: launcher,            // WebUI: from the p0g_app brick; desktop: IoProcessLauncher
  store: store,                  // finds a host that is already running
  command: ProcessCommand('/data/adb/modules/demo/bin/demo',
      arguments: ['serve', '--session-file', '/data/adb/modules/demo/webroot/.run/demo.place.json']),
);
final worker = place.bind(MyServiceWorker());
final facts = await place.facts();          // checked by the root process
if (facts.has(Fact.blockDevices)) { ... }

// Elsewhere: Squadron's own place for this platform.
final local = const LocalPlace().bind(MyServiceWorker());
```

```dart
// cli/bin/demo.dart: the same service, hosted for the process place.
import 'dart:io';

import 'package:squadron_process/io.dart';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'serve') exit(await serve(MyServiceWorker(), args.skip(1).toList()));
}
```

`serve` runs the service in an isolate of the CLI (the generated worker) and
forwards requests from every page link to it. Values crossing the link use a
small binary codec with the value types of Flutter's `StandardMessageCodec`;
custom types need Squadron marshalers, exactly as for Web Workers.

## Places

| Kind | Class | Facts checked by |
|---|---|---|
| `isolate` / `web_worker` | `LocalPlace` | the current context (`dart:io` checks, or browser feature checks) |
| `process` | `ProcessPlace` | the host process, sent in the handshake |

## Facts

Flutter's platform hints don't say what a place can do (WebUI reports web,
AERA reports Linux, neither says "root"). Each place reports its own facts,
each one a check made by that place: `root` (effective uid 0), `block_devices`
(a kernel-listed block device opens for reading), `usb.native`
(`/dev/bus/usb` lists), `usb.web` (`navigator.usb`), `process.spawn` (a
shell runs), `fs.persistent` (the working directory is writable; in a browser,
`navigator.storage.persisted()`), `net` (a non-loopback interface is up; in a
browser, `navigator.onLine`). Absent means not checked and reads as false.
Apps decide with these (`available(facts)` in the bricks), never with
`kIsWeb` / `Platform`. New keys go into the contracts table first.

## Lifetime

The host watches its links. Hidden keeps running: an open link, even an idle
one, holds the host. When the last link closes, the host waits a grace window
(default 10 s, `--grace-ms`) for a page to come back, which covers a reload on
rotation; tasks keep running meanwhile and their results for the old page are
dropped. If no link returns, it cancels every running task and exits: closed
stops. A host nobody connects to exits after `--first-link-grace-ms`.

## Launching

squadron_process defines `ProcessLauncher` and `EndpointStore` and does not
depend on flutter-webui. `IoProcessLauncher` and `FileEndpointStore`
(`package:squadron_process/io.dart`) cover desktop and tests; the WebUI ones
are adapters over flutter-webui's root channel, wired in by the `p0g_app`
brick. What the root channel must provide: [docs/webui-launch.md](docs/webui-launch.md).

## Squadron patch

`Worker.start()` only opens Squadron's own channels. The patch adds
`Worker.channelFactory` (constructor parameter and settable field) and exports
`SquadronCancelationToken` and `StreamId`, which a `Channel` implementation
needs. It lives in `third_party/squadron/patches/` against the release pinned
in `third_party/squadron/PIN` (7.4.4, 4ab7f15) until Squadron accepts it
upstream; Squadron's own VM suite passes with it applied.

```sh
tool/squadron.sh    # patched tree in third_party/squadron/src + pubspec_overrides.yaml
dart test           # VM
dart test -p chrome test/codec_test.dart test/facts_test.dart
```

An app depending on squadron_process needs the same patched Squadron through
`dependency_overrides` until `flutter_p0g` handles it.

## Scope

In: the process channel (client + serve host), the launcher interface, place
facts, the Squadron patch.

Out: strategies, logging conventions and app shape (bricks), the WebUI
launcher adapter (bricks, over flutter-webui's root channel), building and
packaging (`flutter_p0g`), Rust (frb, per app).

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
Apps may link this library statically or dynamically, private apps included,
without releasing their own code or shipping relinking material. Changes to
the library itself stay LGPL.
