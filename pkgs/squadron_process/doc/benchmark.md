# Benchmark: isolate, Web Worker and process places

The same Squadron service (`benchmark/bench_service.dart`) runs in each
place, called through a normal Squadron worker:

- **Call**: 2000 sequential round trips of a no-op call taking and returning
  an int; mean per call.
- **64 KiB stream**: one streaming call yielding 512 chunks of 64 KiB
  (32 MiB); bytes per second as received by the caller.
- **Small items**: one streaming call yielding 50,000 ints; items per second.

Each figure is the median of 5 rounds after one warm-up round.

The process place host is `benchmark/serve.dart` compiled AOT, run as a
separate process. It runs the service in an isolate inside that process, as a
generated worker does. A process-place call therefore makes two hops: a
loopback WebSocket to the host, then an isolate port inside it.

## Results

2026-10-01, 4 vCPU Intel Xeon @ 2.10 GHz (cloud VM), Linux 6.18, Dart 3.13.4,
patched Squadron 7.4.4.

| Runtime | Place | Call (µs, mean) | 64 KiB stream (MiB/s) | Small items (/s) |
|---|---|---:|---:|---:|
| VM 3.13.4 (AOT) | isolate | 31.4 | 3643 | 508k |
| VM 3.13.4 (AOT) | process | 246.9 | 110 | 36k |
| Chromium 141, dart2js | web_worker | 120.4 | 631 | 71k |
| Chromium 141, dart2js | process | 401.3 | 108 | 53k |

## Reading the numbers

- A process-place call costs about a quarter to half a millisecond on
  loopback. That is fine for the work a process place is for (privileged
  operations, file system and device access), and not for chatty
  fine-grained calls: batch those into one call or a stream.
- Bulk data moves at about 110 MiB/s from either runtime. A plain dart:io
  WebSocket on the same machine, with no Squadron and no codec, moves 64 KiB
  frames at about 230 MiB/s, so the transport is the main limit; the codec's
  copies and the isolate hop inside the host take the rest.
- Small items are one WebSocket frame each. The browser client is faster
  than the VM client here, which points at per-frame cost in dart:io's
  WebSocket on the receiving side (inferred, not profiled).
- Wasm (dart2wasm) is not measured yet.

## Running it

```sh
tool/squadron.sh                 # once: patched Squadron
tool/bench.sh /path/to/chromium  # or set CHROME_EXECUTABLE
```

`tool/bench.sh` compiles the host and the VM runner AOT, runs the VM part,
then compiles the page and the Web Worker with dart2js and runs them in
headless Chromium (`benchmark/run_web.dart`). Without a Chromium path it runs
only the VM part. Running Chromium as root needs `--no-sandbox`, which the
runner passes.
