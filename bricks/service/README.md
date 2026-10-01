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
