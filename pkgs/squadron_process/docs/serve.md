# Wiring a CLI's serve command

The process place hosts a Squadron service inside the app's own Dart CLI. The
CLI needs one subcommand that hands its arguments to `serve`:

```dart
// cli/bin/demo.dart
import 'dart:io';

import 'package:squadron_process/io.dart';
import 'package:demo_core/demo_service.dart';      // the generated DemoServiceWorker
import 'package:demo_core/facts.dart';             // the app's FactsCheck

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'serve') {
    exit(await serve(DemoServiceWorker(), args.skip(1).toList(), facts: checkFacts));
  }
  // ... the CLI's other commands
}
```

- `DemoServiceWorker()` is the worker squadron_builder generated for the
  service. `serve` starts it in an isolate of the CLI and forwards every
  client's requests to it. Several services: serve a `LocalWorker` or a small
  facade service that delegates.
- `facts` runs in the CLI process for every handshake; whatever map it returns
  is what clients see in `place.facts()`. squadron_process defines no keys.
  For example, an app that wants `root`, `block_devices`, `usb.native`,
  `usb.web`, `process.spawn`, `fs.persistent` and `net` returns exactly those.
- `serve` returns the exit code: 0 after the lifetime rule stopped it, 64 on
  bad arguments.

## Arguments

```
<cli> serve [--port N] [--session-file PATH] [--launch-id ID]
            [--grace-ms N] [--first-link-grace-ms N]
```

| Option | Default | Meaning |
|---|---|---|
| `--port` | 0 (ephemeral) | loopback port to bind |
| `--session-file` | none | write the endpoint JSON here (atomic rename), delete it on exit |
| `--launch-id` | none | echoed in the ready line and session file; `ProcessPlace` appends it |
| `--grace-ms` | 10000 | how long to wait for a client after the last link closed |
| `--first-link-grace-ms` | 30000 | how long to wait for the first client |

The token comes from `SQUADRON_PROCESS_TOKEN` if set, otherwise it is
generated. It is never accepted on the command line.

## Output

The first stdout line is the ready line:

```json
{"squadron_process":1,"host":"127.0.0.1","port":40111,"token":"...","pid":4243,"launch_id":"8c1f..."}
```

The session file holds the same JSON. Keep anything else the CLI prints in
serve mode on stderr, or at least after the ready line.

## Client side

```dart
final place = ProcessPlace(
  launcher: launcher,                       // see docs/launchers.md
  store: store,                             // reads the session file
  command: ProcessCommand(cliPath, arguments: ['serve', '--session-file', sessionPath]),
);
final worker = place.bind(DemoServiceWorker());
```

`command.arguments` start with `serve` and the options; `ProcessPlace` adds
`--launch-id` itself.

## Depending on squadron_process

Until the Squadron patch is upstream, the app needs the patched Squadron.
From the package or pub workspace root that owns `pubspec_overrides.yaml`:

```sh
dart pub get                                  # resolves against stock Squadron 7.4.4
dart run squadron_process:squadron_patch      # patched tree in .dart_tool + override
dart pub get
```

As a git dependency, pin a full commit SHA:

```yaml
dependencies:
  squadron_process:
    git:
      url: https://github.com/p0g-stack/squadron_process
      ref: <full sha>
```
