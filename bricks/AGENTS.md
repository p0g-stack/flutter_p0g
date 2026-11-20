# bricks: working agreements

Self-contained; no external base file.

- Bricks are versioned; a change bumps the brick version with a changelog line.
- `core/` never imports `package:flutter` (the CLI runs on the plain Dart VM),
  and never uses Flutter-only plugins.
- One app, one CLI: the app's Dart `cli/`, compiled per OS and ABI, is its
  only command-line interface. A Rust crate is used through frb inside that
  CLI (and the app), never shipped as its own binary or CLI, so the shell
  interface is ours everywhere. The `rust/` template stays a library crate.
- Strategies decide with `available(facts)`, never `kIsWeb` / `Platform`.
  `../pkgs/p0g_lints` enforces this and the core rule; a new convention
  that a machine can check becomes a rule there. The brick names the
  `p0g-v*` tag in the root `analysis_options.yaml`; it moves with the
  workspace version, and CI checks the generated manifest against the
  candidate tag.
- Every call logs which strategy ran, in which place, with which facts.
- The separate `demo` repository is generated from `p0g_app`; take a new
  brick version there when the generated shell changes.
- Use existing tools before writing our own (Mason, Squadron, frb).
- Run `tool/ci.sh` before pushing a brick change; it is what CI runs.
- Templates stay `dart format`-clean for a short name; `tool/bootstrap.sh`
  formats the generated workspace, and feature bricks format what they touch.
- Feature bricks add files and insert lines at `// p0g:<slot>` markers in the
  generated workspace; never rename or remove a marker without bumping
  `p0g_app` and every brick that uses it.
- Generated code (`*.g.dart`, compiled web workers) is never committed in a
  generated workspace; bootstrap regenerates it.
- squadron_process is generic: the fact keys and checks, the WebUI launcher
  and its contract (`docs/webui-launch.md`) are ours. Its API is used only in
  `cli/.../serve_command.dart`, `app/lib/places/`, `core/lib/src/places/` and
  `core/lib/src/facts/facts.dart`; keep that seam that small. All the p0g
  packages resolve from one `p0g-v<x.y.z>` tag in every member pubspec, so a
  bump moves that tag and the `^` constraint, not a commit per package. Never
  depend on the `flutter_webui` web plugin from the app: flutter_p0g adds it
  at build time.
