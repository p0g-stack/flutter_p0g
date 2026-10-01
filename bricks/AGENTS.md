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
- Run `tool/ci.sh` before pushing a brick change; it is what CI runs.
- Templates stay `dart format`-clean for a short name; `tool/bootstrap.sh`
  formats the generated workspace, and feature bricks format what they touch.
- Feature bricks add files and insert lines at `// p0g:<slot>` markers in the
  generated workspace; never rename or remove a marker without bumping
  `p0g_app` and every brick that uses it.
- Generated code (`*.g.dart`, compiled web workers) is never committed in a
  generated workspace; bootstrap regenerates it.
- The only files that touch `squadron_process` are the `process_place`
  variants of `cli/lib/src/commands/serve_command.dart` and
  `app/lib/places.dart`. Keep that seam that small.
