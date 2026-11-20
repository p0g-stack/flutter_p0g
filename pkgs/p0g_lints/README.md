# p0g_lints

An analyzer plugin with the two conventions a `p0g_app` workspace keeps.
Both are warnings, so `dart analyze` fails on them.

| Rule | Where | Reports |
|---|---|---|
| `core_imports_flutter` | every file of a package named `*_core` | imports or exports of `package:flutter/`, `package:flutter_test/`, `package:flutter_web_plugins/`, `dart:ui` |
| `strategy_reads_platform` | classes that extend `Strategy` (also through `ReadStrategy` / `WriteStrategy`), and every file under `lib/src/strategy/` | `kIsWeb`, `defaultTargetPlatform`, `TargetPlatform` (Flutter) and `Platform` (`dart:io`) |

Why: core runs on the plain Dart VM in the CLI, and a strategy decides with
`available(facts)`. `kIsWeb` and `Platform` tell what Dart was compiled for,
not what a place can do (WebUI says web, AERA says Linux, neither says root).

## Use

The `p0g_app` brick turns it on. By hand, in the workspace root's
`analysis_options.yaml`:

```yaml
plugins:
  p0g_lints:
    git:
      url: https://github.com/p0g-stack/bricks
      path: packages/p0g_lints
      ref: <commit>
```

A member package with its own `analysis_options.yaml` includes the root one
(`include: [package:flutter_lints/flutter.yaml, ../analysis_options.yaml]`),
or the plugin does not run there. The first `dart analyze` builds the plugin
(about a minute); later runs reuse it.

Built on `analysis_server_plugin` 0.3 (analyzer 14), the Dart 3.13 plugin
API. `tool/ci.sh` checks both rules against a generated workspace.
