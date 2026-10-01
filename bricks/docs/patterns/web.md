# Patterns: apps in a browser tab

For a p0g app built with `flutter_p0g build web` and served from any static
host. The local place is a Squadron Web Worker; there is no process place,
so `places.lasting` is the worker and work stops when the tab closes. The
crate in `rust/` runs as single-threaded wasm, in the page and in each
worker, with no COOP/COEP headers. Nothing here is a brick.

## Long work is a service stream

A job that takes more than a moment (extracting an OTA, hashing a large
image, a flash) is a service method that returns a `Stream` of progress and
ends with the result. The page shows the stream and cancels by cancelling
its subscription; Squadron carries the cancel to the worker. Don't poll a
status method. The same method works unchanged in an isolate or the process
place on other platforms.

## Hand the worker the file, not the bytes

A file the user picks in the page (`file_selector`'s `XFile`, a `File` from
a drop) goes to the worker as the browser's own `File` or `Blob` object
(a `JSObject`). Squadron passes it without copying, and the worker reads
only the slices it needs (`blob.slice(start, end)`). Never read a large file
into a `Uint8List` in the page to send it: that copies it twice and holds it
in memory. Output that is too big for a download goes to a directory the
user picks (File System Access, Chromium) or to OPFS.

## Rust loads when it is first used

`Fact.native` only asks whether the wasm was shipped; it doesn't download
it. A strategy that calls Rust awaits `loadNative()` first, so the wasm is
fetched and instantiated in the place that uses it, the first time it does.
Keep it that way: a page that never takes the Rust strategy never pays for
the download.

With `--wasm`, the workers are dart2wasm too, and the crate doesn't load
inside them yet: Squadron starts a dart2wasm worker from a `blob:` URL, so
`../pkg/` has nothing to resolve against. Strategies fall back as they
should (`Fact.native` is false there). The default dart2js build has no
such gap.

## Check the input inside the plan

A write's `plan` opens the input and checks it before anything is
confirmed: the image's header, its size against the target partition, and
its hash when the source gives one. Each check is a step the user sees. A
bad file then fails at the plan, with nothing written, instead of halfway
through the write.

## Keep the tab alive while writing

While a write runs, the app holds a screen wake lock
(`navigator.wakeLock.request('screen')`) and a leave guard
(`window.onbeforeunload`), and releases both when the stream ends, however
it ends. A sleeping laptop or a closed tab in the middle of a flash is a
user problem the app can prevent. Both are app code through `package:web`;
the bricks don't ship them.

## Devices

A write to a device over WebUSB follows [devices.md](devices.md): it waits
for a connected phone, names the device in its plan, and sorts errors by
blame while keeping the original error.
