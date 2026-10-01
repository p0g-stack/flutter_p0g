## 0.1.0

- First release (unpublished).
- Process place: `ProcessPlace` and `LocalPlace`; `Place.bind(worker,
  service:)` points a generated Squadron worker at a place.
- `ProcessChannel`: a Squadron `Channel` over a loopback WebSocket with a
  token handshake, binary codec, cancellation and streaming.
- Host side (`package:squadron_process/io.dart`): `serve` for a CLI's serve
  subcommand, `startServe`, `PlaceHost` with the grace-window lifetime, several
  named services per process.
- Facts: a neutral map checked by each place (`FactsCheck`) and sent in the
  handshake.
- Launchers: `IoProcessLauncher`, `ElevatedLauncher` (`PkexecLauncher`,
  `SuLauncher`, `MacAdminLauncher`, `WindowsRunAsLauncher`), launch ids and
  `FileEndpointStore` for front-ends that hide stdout.
- A worker reconnects after its link drops: the next call opens a new link,
  starting a new host if the old one is gone (one for all workers that lost
  it). `ProcessHandshake` and `ProcessChannel.fromHandshake(reconnect:)`.
- The host refuses malformed or oversized hellos and survives malformed
  messages after the handshake; the client rejects a malformed welcome.
- Service log records reach the client worker's `channelLogger` over the
  process link (`log` frame), as from an isolate or Web Worker; the hosted
  worker's own `channelLogger` still gets them. Each client process gets a
  record once, however many workers it bound (`clientId` in the hello,
  `processClientId`, `ProcessPlace(clientId:)`).
- Benchmark of isolate, Web Worker and process places on the VM and in
  Chromium (`benchmark/`, `tool/bench.sh`, doc/benchmark.md).
- `squadron_patch` executable and the Squadron 7.4.4 channel-factory patch.
