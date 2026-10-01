# strategy

Adds an objective and its strategies to a `p0g_app` workspace (0.2.0 or
later). Run it in the workspace root:

```sh
mason make strategy --name fetch_partition --strategies '["dd", "fastboot_fetch"]'
mason make strategy --name flash --write true --strategies '["dd"]'
```

It writes `core/lib/src/strategy/<name>.dart` (the objective and one class
per strategy) and `core/test/<name>_test.dart`, and exports it from the core.

Conventions it stamps:

- **Decide by facts.** Each strategy lists the facts it needs in `requires`;
  `available(facts)` checks them (override it for more). Never `kIsWeb` or
  `Platform`. The first available strategy, in the order given, runs.
- **Host versus device is a strategy choice.** `dd` in the root process and
  `fastboot fetch` from a host are two strategies of one objective, not two
  code paths in a platform layer.
- **Device writes: plan, then confirm, then receipt.** With `write`, the
  strategies are `WriteStrategy`: `plan` describes the steps and changes
  nothing; the UI or CLI shows them and makes a `Confirmation`;
  `Objective.apply` checks it is for this plan, writes, and returns a
  `Receipt`.
- **Accounting.** Every run logs a `StrategyRun` on `objective.<name>`: which
  strategy, in which place, with which facts, what was skipped and why.

Run an objective inside a service, with the facts of the place the service
runs in: `objective.run(input, await PlaceInfo.current())`.
