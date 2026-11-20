# Transport

The process place speaks its protocol over a `PlaceLink`: one duplex stream
of whole binary frames. The default link is a WebSocket to 127.0.0.1
(`connectWebSocket` on the client, `startServe`/`serve` on the host), but
nothing above the link depends on that:

- Client: `ProcessPlace(connector: (endpoint) async => myLink)` replaces the
  WebSocket. The handshake, reconnect, cancellation and streaming run
  unchanged over whatever link the connector returns.
- Host: `PlaceHost.accept(link)` takes a link from any source, so a host can
  serve the same services over a second transport next to the WebSocket.

A link must deliver frames whole and in order, and signal close (`frames`
done) when the other end goes away. It need not be a socket.

## Browsers and loopback (Local Network Access)

Chromium 141 ships Local Network Access: a page loaded from a public origin
needs the user's "local network access" permission before it can reach
loopback or private addresses, WebSocket included. A page served from
loopback itself, or a native client (Dart VM, AOT, Flutter desktop), is not
affected.

If an embedding's web view applies the same rule to its pages (Android
System WebView may follow Chromium), the default WebSocket link can be
blocked with no prompt the user can answer. Status: not observed yet; whether
Android WebView enforces it on embedded pages is being checked.

The fallback is a different `PlaceLink`, not a different protocol. Anything
the page can already use to reach the host process will do, for example a
bridge the embedding exposes to run commands or relay messages: frames go
out through the bridge to a small relay next to the host, which hands them to
`PlaceHost.accept` on a link of its own. Such a link usually polls or batches
and is slower than the WebSocket (see benchmark.md for the WebSocket
baseline); its latency is the bridge's. Building one for a given embedding
belongs to that embedding, not to this package.
