# template-app: working agreements

Extends `~/.agents/AGENTS.md`. Seed; refine per directory as the nest fills in.

- Stay bare. A feature that is not needed to prove "builds and runs on every
  target" goes to `surfaces/example` or `surfaces`.
- Every target builds in CI on every PR, or the PR says which one cannot and why.
- The `surfaces` pin moves in one commit for both halves, with the changelog
  line that justifies it.
- `docs/` sketches are prose and signatures, not code that compiles here.
