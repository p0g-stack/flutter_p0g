# Launching the process place on WebUI

What squadron_process needs from flutter-webui's root channel
(`flutter_webui_root`) to start and find an app's root process. squadron_process
owns this contract; flutter-webui implements the root-channel side, and the
`p0g_app` brick wires a small adapter (`ProcessLauncher` + `EndpointStore`) over
the root-channel client into the app. squadron_process never imports
flutter_webui.

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

```
<module>/bin/<app> serve --session-file <module>/webroot/.run/<app>.place.json
                         [--port N] [--grace-ms N] [--first-link-grace-ms N]
```

- Binds 127.0.0.1 only, on an ephemeral port unless `--port` is given.
- Token: generated (32 random bytes, base64url) unless
  `SQUADRON_PROCESS_TOKEN` is set in its environment. Never taken from argv,
  which any app can read from `/proc/<pid>/cmdline`.
- Prints the ready line (endpoint JSON) as the first stdout line.
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
