# surfaces: working agreements

Extends `~/.agents/AGENTS.md`. Seed; refine per directory as the nest fills in.

- Spec before code. A protocol, capability, ABI or layout change lands as one
  commit touching `spec/`, `spec/fixtures/`, the Rust half and the Dart half.
- One table per fact. Capability ids, error codes, job states, quoting and
  naming rules each have exactly one source; the other language reads or
  generates from it, never re-declares it.
- Nothing app-specific. If a change only makes sense for one app, it belongs in
  that app's `rust/` or `lib/`.
- Root is a boundary. Any string that reaches `ksu.exec` or the worker is
  quoted by the library, not the caller. Ops that write declare it; unclassified
  ops are refused, not assumed read-only.
- Generated code is checked, not trusted: CI regenerates and diffs.
- Every host claim in a PR is backed by a run: e2e over the fake profiles, the
  AERA simulator, or a `certify` receipt.
