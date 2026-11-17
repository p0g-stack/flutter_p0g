# 0.5.0

- `panel` (default true): with `panel: false` the brick adds no app panel
  and touches neither `app/lib/panels/panels.dart` nor its format list; the
  core service, its test, the CLI command and the `serve` entry stay.
- pre_gen checks every file and `// p0g:` marker the insertions need
  (the panel's only with `panel`) before Mason writes anything, and aborts
  naming what is missing. post_gen only applies those checked insertions,
  still skipping lines already there, and formats. Works with p0g_app
  0.9.0 `sample: false`, whose registry and panel list start empty.

# 0.4.0

- Logs come back: the service's constructor calls `forwardLogs()`, and the
  panel and `serve` wrap its worker in `withLogs(...)`. Needs p0g_app 0.8.0.

# 0.3.0

- README "Shaping the methods" and the service's doc comment: process-place
  call cost and link throughput from squadron_process's benchmark; batch, or
  stream, rather than chatty calls.

# 0.2.0

- For `p0g_app` 0.3.0: the `serve` entry is a worker instance, and the panel
  binds with `service: '<name>'` on the place the user picked.

# 0.1.0

- Initial brick: a Squadron service in `core/`, its test, a CLI command, a
  `serve` entry and an app panel, wired in at the `// p0g:` markers of a
  `p0g_app` 0.2.0 workspace.
