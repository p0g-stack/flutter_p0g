# squadron_process: working agreements

Self-contained; no external base file.

- Extend Squadron, don't replace it. Anything Squadron already does (pools,
  cancellation, streams, exceptions, marshalling, codegen) is used as is.
- The patch stays minimal and upstreamable: a channel-factory hook, nothing
  app-specific.
- A place reports facts it has checked, never facts guessed from the platform.
- Nothing app-specific. Strategies and conventions belong in the bricks.
- Unofficial: the README says so; never imply Squadron's author endorses it.
