# p0g

p0g builds stock Flutter apps for two Android hosts that are not official
Flutter platforms:

- **WebUI**, a KernelSU-style root module whose page runs in the manager's
  WebView;
- **AERA**, a recovery plugin.

One Flutter CLI adds the platform folders, builds the module and the plugin,
and runs the app with hot reload. Everything the two targets need — the WebUI
embedder, its plugin implementations, the patched web SDK, the patched sources,
the app template — lives in this repository, so the packages ship and change
together.

The org's documentation lives in
[p0g-stack/.github/docs](https://github.com/p0g-stack/.github/tree/main/docs):
repository map, bump and release workflow, upstream policy, decisions.

## Layout

| Path | What |
|---|---|
| `pkgs/flutter_p0g` | the CLI executable; a launcher that runs the tool against the installed Flutter SDK |
| `pkgs/flutter_p0g_tool` | the implementation: flutter_tools plus `create`, `build`, `run`, `install`, `devices`, `logs`, `precache` |
| `pkgs/flutter_webui{,_client,_root}` | the WebUI embedder: handlers on patched `web_ui`, the app-facing client, the root channel |
| `pkgs/webui/` | one `<plugin>_webui` package per stock plugin the WebView cannot serve |
| `pkgs/squadron_process` | a third Squadron place: another process, optionally elevated |
| `pkgs/patched_source` | versioned-source materialization for the carriers that need it |
| `pkgs/p0g_lints` | analyzer rules for generated apps |
| `web_sdk/` | the patched Flutter web SDK: `VERSION`, `patches/`, builder |
| `bricks/` | Mason templates for an app workspace (outside the pub workspace) |
| `third_party/<upstream>/` | every carried patch series: `PIN`, `patches/`, optional notes |
| `tool/patches.sh` | checkout, rebase and export those series |
| `artifacts.lock.json` | url, sha256 and size of every binary the stack consumes |

`pkgs/*`, `web_sdk/` and the launcher are one pub workspace with one lock
file; siblings resolve by relative `path:`. The implementation
(`pkgs/flutter_p0g_tool`) resolves on its own against the installed SDK's
`flutter_tools` (see its README). `bricks/` and `third_party/` stay outside
the workspace.

## Using it from another repository

Every package in `pkgs/` is versioned in lockstep: one version, one tag
`p0g-v<x.y.z>`. Depend on one package by URL, path and tag pattern:

```yaml
dependencies:
  squadron_process:
    git:
      url: https://github.com/p0g-stack/p0g
      path: pkgs/squadron_process
      tag_pattern: p0g-v{{version}}
    version: ^0.9.0
```

pub resolves the tag, then keeps that package's `path:` siblings at the same
commit. A direct dependency of yours on a sibling comes from the other tag, so
a package that appears both ways needs one source for both: the generated app
workspace therefore carries

```yaml
# in the generated cli/pubspec.yaml:
dependency_overrides:
  flutter_webui_root:   # flutter_webui_client's sibling
    git:
      url: https://github.com/p0g-stack/p0g
      path: pkgs/flutter_webui_root
      tag_pattern: p0g-v{{version}}
    version: ^0.9.0
  patched_source:       # squadron_process's sibling
    git:
      url: https://github.com/p0g-stack/p0g
      path: pkgs/patched_source
      tag_pattern: p0g-v{{version}}
    version: ^0.9.0
```

They pin the sibling to the same tag instead of letting pub mix a tag with a
commit-pinned path edge. A tool that adds itself at build time only
(`flutter_webui`) never appears in a consumer's manifest.

An analyzer plugin cannot use `tag_pattern` (the analysis server resolves it in
a synthetic package below the SDK floor the pattern needs), so
`analysis_options.yaml` names the same tag as `ref:`.

## Installing the CLI

```sh
dart pub global activate --source git https://github.com/p0g-stack/p0g --git-path pkgs/flutter_p0g
# a release: add --git-ref p0g-v<x.y.z>
```

`flutter_p0g` needs the Flutter release the package declares; it refuses any
other. See [pkgs/flutter_p0g/README.md](pkgs/flutter_p0g/README.md).

## Installing the bricks

```sh
mason add -g p0g_app  --git-url https://github.com/p0g-stack/p0g --git-path bricks/p0g_app  --git-ref p0g-v<x.y.z>
mason add -g service  --git-url https://github.com/p0g-stack/p0g --git-path bricks/service  --git-ref p0g-v<x.y.z>
mason add -g strategy --git-url https://github.com/p0g-stack/p0g --git-path bricks/strategy --git-ref p0g-v<x.y.z>
```

Bricks are not part of the package version; `bricks/README.md` and each
brick's `CHANGELOG.md` carry their own versions. The commands above take the
repository tag, so a brick added later is available from a newer tag.

Then walk
[bricks/docs/new-app.md](bricks/docs/new-app.md) from an empty folder to a
module on the device.

## Working on the repository

Flutter 3.50.0 (`.fvmrc`), a bootstrap step for the patched Squadron, then a
workspace resolve:

```sh
pkgs/squadron_process/tool/squadron.sh
flutter pub get
pkgs/flutter_p0g_tool/tool/resolve.sh
```

`AGENTS.md` has the rest: tests, patch series, the rules changes land by.

## Licences

Root `LICENSE` and `LICENSE.exception`: `LGPL-3.0-or-later WITH
LGPL-3.0-linking-exception`. `bricks/`, `pkgs/flutter_webui`,
`pkgs/squadron_process` and `pkgs/webui` each carry their own copy of both
files, so a published unit is self-contained. Apps may link the libraries,
private apps included, without releasing their own code; changes to a library
stay LGPL.
