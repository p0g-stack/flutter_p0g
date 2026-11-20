# p0g

p0g builds Flutter apps for WebUI and AERA. Start with the [CLI guide](pkgs/flutter_p0g/README.md) for setup and commands.

| Location | Purpose |
| --- | --- |
| `pkgs/flutter_p0g` | Flutter CLI and target packaging |
| `pkgs/patched_source` | Reproducible source patches and pub overrides |
| `pkgs/squadron_process` | Process workers for Squadron |
| `pkgs/flutter_webui{,_client,_root}` | WebUI plugin, page client and root channel |
| `pkgs/webui/` | WebUI platform plugins and shared utilities |
| `pkgs/p0g_lints` | Analyzer rules for generated projects |
| `bricks/` | Mason templates (outside the pub workspace) |
| `web_sdk/` | Patched Flutter web SDK builder |

For workspace development, run `pkgs/squadron_process/tool/squadron.sh`, then `flutter pub get` from the repository root with Flutter 3.50.0. The CLI resolves separately in `pkgs/flutter_p0g` with Flutter 3.47.9.
