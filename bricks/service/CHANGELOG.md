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
