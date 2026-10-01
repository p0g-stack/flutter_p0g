# WebUI launcher contract

What the `p0g_app` brick's WebUI launcher (`app/lib/places/webui_launcher.dart`:
`WebUiLauncher` + `WebUiSessionStore`) needs from flutter-webui's root channel
(`flutter_webui_root`, contract v1 in flutter-webui's `docs/root-channel.md`)
to start and find an app's root process. bricks owns this contract; the
generic launcher rules are squadron_process's `docs/launchers.md`.

## What the page does

```
page (Flutter web, manager WebView)
  ProcessPlace(launcher: WebUiLauncher, store: WebUiSessionStore, command: ...)
    1. store.read()                 -> endpoint of a host that is still running?
    2. if none, or it refuses:
       launcher.launch(command)     -> root channel starts `<cli> serve ...` as root
       first JSON line on stdout    -> {"squadron_process":1,"port":..,"token":..,"pid":..}
    3. WebSocket ws://127.0.0.1:<port>/squadron, hello with the token,
       welcome with the root process's facts
```

A page reload (Next / WebUI X recreate the activity on rotation) runs the same
steps; step 1 finds the running host, so tasks started before the reload keep
going in it.

## What the root channel must provide

1. **Start a process detached, as root.** Arguments: absolute executable path,
   argv, environment (merged over a clean root environment), working
   directory. "Detached" means it survives the root channel's own shell going
   away (WebUI X closes its shell when the page stops if
   `killShellWhenBackground` is not false) and the page's WebSocket closing:
   new session (`setsid`), stdin from `/dev/null`, not a child the channel
   reaps on exit. squadron_process's own lifetime rule ends it.
2. **Stream its stdout as lines** back to the page until the page stops
   listening, and report the exit code if it exits while the page is still
   listening. The host prints its ready line first; everything after it is
   logs. stderr may be dropped or logged by the channel.
3. **Read one small text file under the module's directory**, for the session
   file below, or serve it to the page the way the channel serves its own
   `webroot/.run/session.json`. Either works; reading through the channel
   avoids exposing the token on the manager's HTTP origin.

Nothing else: no job store, no restart policy, no knowledge of Squadron.

## What the host (the app's CLI) does

`bin/<app>` is a launcher `flutter_p0g build webui` writes: a `/system/bin/sh`
script that `exec`s `<module>/bin/<abi>/dartaotruntime <app>.aot "$@"` (abi from
`getprop ro.product.cpu.abi`), so the root channel's detached wrapper sees the
host's own exit code. flutter_p0g names it after the first `executables:` key
of `cli/pubspec.yaml`; the brick declares `<app>: <app>` there, so both sides
read the same name. One host serves all of the app's services;
a client names the service when it binds a worker.

```
<module>/bin/<app> serve --session-file <module>/webroot/.run/<app>.place.json
                         --launch-id <id, appended by ProcessPlace>
                         [--port N] [--grace-ms N] [--first-link-grace-ms N]
```

- Binds 127.0.0.1 only, on an ephemeral port unless `--port` is given.
- Token: generated (32 random bytes, base64url) unless
  `SQUADRON_PROCESS_TOKEN` is set in its environment. Never taken from argv,
  which any app can read from `/proc/<pid>/cmdline`.
- Prints the ready line (endpoint JSON, with the launch id) as the first
  stdout line. `WebUiLauncher` passes the command through unchanged, so the
  `--launch-id` that `ProcessPlace` appends reaches the host.
- Writes the same JSON to `--session-file` by atomic rename, and deletes it on
  exit if it still names this host.
- Refuses a link whose hello carries the wrong token.
- Lifetime: keeps running while any page link is open (hidden keeps going);
  when the last one closes, waits `--grace-ms` (default 10 s) for a link to
  come back; if none does, cancels every running task and exits (closed
  stops). A host nobody connects to exits after `--first-link-grace-ms`
  (default 30 s). SIGTERM / SIGINT do the same as an expired grace window.

## Open, for devicelab

- The uid check the roadmap names for the root channel (`/proc/net/tcp`
  owner of the connecting socket == the manager's uid) is not done by the
  host yet; the token is the only gate.
- Whether WebUI X's `pauseTimers()` also delays WebSocket callbacks while the
  page is hidden (tasks keep running in the host either way).
