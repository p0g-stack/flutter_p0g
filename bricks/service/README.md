# service

Adds a Squadron service to a `p0g_app` workspace (0.3.0 or later). Run it in
the workspace root:

```sh
mason make service --name partitions
bash tool/bootstrap.sh     # or: (cd core && dart run build_runner build) && bash tool/build_workers.sh
```

| File | What |
|---|---|
| `core/lib/src/service/<name>_service.dart` | the service (`@SquadronService`), one example method |
| `core/test/<name>_service_test.dart` | in-process and in-isolate tests |
| `cli/lib/src/commands/<name>_command.dart` | `<app> <name> ...`, calling the service in-process |
| `app/lib/panels/<name>_panel.dart` | a panel bound to the place the user picked |

The hooks find the app name from `core/pubspec.yaml` and insert the export,
the command, the `serve` entry and the panel at the `// p0g:` markers, then
format what they touched.

## Shaping the methods

The same methods run in an isolate, a Web Worker or the CLI's `serve`
process, but they do not cost the same. squadron_process measured
([doc/benchmark.md](https://github.com/p0g-stack/squadron_process/blob/5d41a990abd60df81fcc4d7cd4841bd146e3f5d2/doc/benchmark.md)):
a process-place call costs a few hundred microseconds on loopback (about
250 µs from the VM, 400 µs from a page) against about 30 µs for an isolate,
and the link moves about 110 MiB/s.

- Make one call do a whole job: `readPartition(name)`, not a call per block.
  Batch small requests into one call that takes a list.
- Return progress and large data as a `Stream`, in chunks of tens of KiB,
  rather than as many calls or one huge value.
- Keep chatty, fine-grained work (per-item callbacks, polling) inside the
  service, and send the UI only what it shows.
