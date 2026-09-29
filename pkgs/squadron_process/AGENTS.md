# surfaces: working agreements

Extends `~/.agents/AGENTS.md`. Seed; refine per directory as the nest fills in.

- If Flutter has a concept for it, it does not belong here; fix the embedder.
- Spec before code. A protocol, capability, effect or layout change lands as
  one commit touching `spec/`, `spec/fixtures/`, the Rust half and the Dart half.
- One table per fact. Capability ids, error codes, job states, effects and
  quoting rules each have exactly one source; the other language generates
  from it, never re-declares it.
- Effects are a closed enum. An op without one is refused; `Device` ops go
  plan, confirm, execute, verify, receipt, and the confirm token is the hash
  of the plan shown.
- Nothing app-specific. If a change only makes sense for one app, it belongs
  in that app's `rust/` or `lib/`.
- Generated code is checked, not trusted: CI regenerates and diffs.
- Every host claim in a PR is backed by the example's e2e run or a host report
  under `docs/hosts/`.
