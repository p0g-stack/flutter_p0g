# bricks: working agreements

Self-contained; no external base file.

- Bricks are versioned; a change bumps the brick version with a changelog line.
- `core/` never imports `package:flutter` (the CLI runs on the plain Dart VM),
  and never uses Flutter-only plugins.
- Strategies decide with `available(facts)`, never `kIsWeb` / `Platform`.
- Every call logs which strategy ran, in which place, with which facts.
- `demo` is generated from `p0g_app`; CI regenerates it and diffs, so a brick
  change and its demo change land together.
- Use existing tools before writing our own (Mason, Squadron, frb).
