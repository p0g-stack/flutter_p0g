# Patterns: which place runs what

A p0g app puts each service in a place. The local place is an isolate on
the Dart VM, or a Web Worker in a browser. The process place is the app's
CLI in `serve` mode; on WebUI it runs as root. `Places` in the generated app
holds both.

## Work that must keep going runs in the process place

Use `places.lasting` for anything that has to make progress while the user
looks away: a download, a flash, a long copy, a background task. It gives
the process place when there is one, and the local place otherwise.

A Web Worker belongs to the page, so it stops when the page stops:

- WebUI X pauses the page's timers while it is hidden, which stalls a
  worker's work.
- KernelSU Next and WebUI X recreate the page on rotation, which ends the
  worker and its task.

The process place belongs to no page. When the page is hidden it keeps
running. When the page is closed it stops after its grace window. A
reloaded page finds it again through its session file (see
[../webui-launch.md](../webui-launch.md)).

The local place is still right for quick work the page waits on, such as
parsing, hashing a small input or building a preview. Work that needs root
goes to the process place anyway.

## Logs come back from every place

Each place runs in its own isolate or worker, so a record logged there
never reaches the app's `logTo` on its own. The bricks wire two halves:

- The service's constructor calls `forwardLogs()`.
- The caller wraps each worker in `withLogs(...)` before it starts. The
  panels do this, and so does `serve` for the services it hosts.

A service made with `mason make service` gets both. Records reach the app's
log from every place, with their logger names and levels intact. That
includes the process place, whose host relays them over the link
(squadron_process 5d41a99). Records from services hosted by `serve` also
reach the CLI's own log.
