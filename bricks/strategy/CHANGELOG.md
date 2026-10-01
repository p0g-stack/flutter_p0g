# 0.2.0

- Write stubs say how to pin a device outside this place; README covers
  waiting availabilities. Needs `p0g_app` 0.7.0 (`Availability.waiting`).

# 0.1.0

- Initial brick: an `Objective` with one strategy per name, read
  (`ReadStrategy.run`) or device write (`WriteStrategy.plan` / `write`,
  applied only with a `Confirmation`), and its test, exported at the
  `// p0g:exports` marker of a `p0g_app` 0.2.0 workspace.
