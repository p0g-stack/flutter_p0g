# p0g: working agreements

One repository, one version: `pkgs/*`, `web_sdk/` and the launcher
(`pkgs/flutter_p0g`) resolve as one workspace and ship under the tag
`p0g-v<x.y.z>`. The truth about what is pinned lives in the lock files —
`.fvmrc` (Flutter), `artifacts.lock.json` (binary url/sha256),
`third_party/<upstream>/PIN` (carried commits) and the pubspecs. No document
repeats those values.

## Local commands

Run from the repository root, with the Flutter SDK on `PATH`:

```sh
flutter --version                         # must print the version in .fvmrc
pkgs/squadron_process/tool/squadron.sh    # once after cloning; again when third_party/squadron changes
flutter pub get                           # the workspace
pkgs/flutter_p0g_tool/tool/resolve.sh     # CLI implementation against this SDK's flutter_tools
```

`tool/squadron.sh` writes `pkgs/squadron_process/pubspec_overrides.yaml` and
needs it before `pub get`; it leaves a file it did not write alone.

Tests (unit tests only; no e2e, no devices):

| Where | Command |
|---|---|
| `pkgs/flutter_p0g` | `dart test` |
| `pkgs/flutter_p0g_tool` | `dart test` |
| `pkgs/patched_source` | `dart test` |
| `pkgs/squadron_process` | `dart test -p vm`, plus `dart test -p chrome test/codec_test.dart test/facts_test.dart` (needs Chrome; `CHROME_EXECUTABLE` when `google-chrome` is not on `PATH`) |
| `pkgs/flutter_webui{,_client,_root}` | `dart test` (`flutter test` for the web plugin) |
| `pkgs/webui/webui_app_plane` | `dart test` |
| `pkgs/webui/<plugin>_webui` | `flutter test` |
| `bricks/` | `cd bricks && bash tool/ci.sh` (generates apps and tests them as an outside consumer; needs Chrome, cargo, wasm-pack for the Rust variants) |

## Carried patches

A patch series is `third_party/<upstream>/{PIN,patches/}`. `PIN` names the
upstream repository, the full commit and the patched package; `patches/` is
`git format-patch` output, one commit per file. `web_sdk/patches` is the one
series that is not upstreamable, so it lives with the SDK it patches and its
base is `web_sdk/VERSION`.

```sh
tool/patches.sh <upstream> checkout   # .upstream/<upstream>, branch p0g/<upstream> at PIN
tool/patches.sh <upstream> export     # regenerate patches/ from that branch
```

`tool/patches.sh <upstream> push <slug>` force-pushes that branch to our fork
(`p0g-stack/<upstream>`) as `<slug>`, for someone who wants to read it. It is
not part of a normal bump.

Never edit a `.patch` file. Edit the commit on `p0g/<upstream>`, `export`, and
commit `PIN` and `patches/` together; `checkout` then `export` must leave the
tree clean. The commit message is the upstream PR draft: subject is the title,
body says why, what and how it was checked. A bump rebases every series onto
the newest stable release; a patch upstream already released is dropped by the
rebase. The full policy is in
[p0g-stack/.github/docs/upstreams.md](https://github.com/p0g-stack/.github/blob/main/docs/upstreams.md).

## Landing changes

- **Local first.** Run the package tests, `dart analyze` and any build the
  change touches before pushing. CI is the final check, not a debugger.
- **One PR per series.** Work in your own checkout (ovnfs) on a branch, push
  the branch, open one PR. `main` takes PRs only.
- **Merge commits.** GitHub's rebase merge re-creates commits without their
  signatures; a merge commit keeps the agent-signed commits and GitHub signs
  the merge.
- **Expensive workflows are dispatch-only** (lab runs, engine and kit builds,
  releases, promotion). The integrator dispatches them; a pull request does
  not trigger them.
- Every commit is signed with the agent key; `main` is protected.

## Conventions

- **Parity is the bar.** On each target, the same experience and the same
  flags as the stock `flutter` tool gives on an official platform. A gap is
  documented, never papered over.
- **Pattern first.** Check how `flutter_tools`, `flutterpi_tool`,
  flutter-elinux or flutter-tizen do it, and do it their way. A new command is
  a `FlutterCommand`; a new target reuses the closest stock build and adds
  only packing. A default changes only where the target cannot work with it,
  with the reason beside the override.
- **The platform folders belong to the app.** `create` never overwrites
  without `--overwrite`; `build` only fills in build variables.
- **Hosts' own affordances.** App code calls the standard API; the embedder
  answers with what the host offers, detected by probing, never by a manager's
  name.
- **One app, one CLI.** A generated app's Dart `cli/` is its only command
  line, on the device as root too. Rust comes in as a library through frb.
- **Verify with fakes here, devices in devicelab.** Unit tests against fakes
  and in-memory files back every claim in this repository; anything that
  needs a device, a manager or a browser names where it was run.

Package rules live beside the code: `pkgs/flutter_webui/AGENTS.md`,
`pkgs/squadron_process/AGENTS.md`, `pkgs/webui/AGENTS.md`,
`bricks/AGENTS.md`.
