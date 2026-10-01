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
- Benchmark of isolate, Web Worker and process places on the VM and in
  Chromium (`benchmark/`, `tool/bench.sh`, doc/benchmark.md).
- `squadron_patch` executable and the Squadron 7.4.4 channel-factory patch.
