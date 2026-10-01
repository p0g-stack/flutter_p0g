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

## Facts

Flutter's platform hints don't say what a place can do (WebUI reports web,
AERA reports Linux, neither says "root"). Each place reports its own facts when
it connects: `root`, `block_devices`, `usb.native`, `usb.web`, `process.spawn`,
`fs.persistent`, `net`, ... Apps decide with these (`available(facts)`), never
with `kIsWeb` / `Platform`.

## Lifetime

The process watches its client link. If the page goes away and doesn't come
back within a short grace window (a reload on rotation), it cancels its tasks
and exits: hidden keeps running, closed stops.

## Squadron patch

`Worker.start()` only opens Squadron's own channels. A pinned patch adds a
pluggable channel factory; it lives in `third_party/squadron/patches/` until
Squadron accepts it upstream.

## Scope

In: the process channel (client + serve host), launching (WebUI root channel,
later `pkexec`), place facts, the Squadron patch.

Out: strategies, logging conventions and app shape (bricks), building and
packaging (`flutter_p0g`), Rust (frb, per app).

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
Apps may link this library statically or dynamically, private apps included,
without releasing their own code or shipping relinking material. Changes to
the library itself stay LGPL.
