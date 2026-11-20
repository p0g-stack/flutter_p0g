# flutter_p0g_tool

The implementation behind `flutter_p0g`. It imports `flutter_tools` as a
library and adds the commands that make a stock Flutter app work on the two
p0g hosts, the way `flutterpi_tool` adds its target: everything stock keeps
its meaning, and only packing, the host folders and the artifacts differ.

`flutter_p0g` itself is a launcher
([pkgs/flutter_p0g](../flutter_p0g/README.md)); this package is never
activated directly.

## Resolving it

`flutter_tools` is an SDK package (`sdk: flutter`), and SDK-source packages
cannot have relative path dependencies, so this package resolves on its own
against one SDK:

```sh
pkgs/flutter_p0g_tool/tool/resolve.sh      # FLUTTER_ROOT, else flutter on PATH
```

It writes `pubspec_overrides.yaml` (gitignored) with `flutter_tools` pointing
at `<FLUTTER_ROOT>/packages/flutter_tools`, then runs `flutter pub get`.
Extra arguments go to `pub get`. A `pubspec_overrides.yaml` the script did not
write is left alone, and one that overrides `flutter_tools` is kept.

The launcher does the same thing in a throwaway host package, which is why an
activated CLI needs no checkout.

## Commands

Every target command works from the app's directory (the one with the
`pubspec.yaml`); the workspace root is not an app.

| Command | Does |
|---|---|
| `create [<dir>]` | adds `webui/` and `aera/` (and `web/` when missing) to an existing app, like `flutter create --platforms`. `--platforms`, `--author` (module.prop), `--overwrite` |
| `build web` | stock `flutter build web`, plus the app's Rust wasm and Squadron Web Workers |
| `build webui` | `build web` with WebUI defaults, then the module zip |
| `build aera` | `flutter build bundle` for linux-arm64, packed with the AERA runtime kit into a `.aerap` |
| `run` | the app in a WebUI page with hot reload, from a dev server on this machine |
| `run --aera` | a debug `.aerap` in AERA recovery, started over its RPC, then `flutter attach` |
| `install [<zip\|aerap>]` | the module through the device's root manager, or the plugin into AERA's store |
| `devices` | adb devices, each probed for a root manager or AERA's RPC channel |
| `logs` | the module's root process and page console, or `/tmp/recovery.log` |
| `precache` | downloads or builds what the targets need |

`flutter_p0g help <command>` lists the flags. The ones this tool adds:

| Command | Options |
|---|---|
| `build webui` | `--cli-format=aot\|exe`, `--abi=arm64-v8a,x86_64`, `--[no-]device-rust`, `--device-rust-libs=<dir>`, `--[no-]update-json`, `--update-url=<url>` |
| `build aera` | `--payload-url=<url>`, `--[no-]device-rust`, `--device-rust-libs=<dir>` |
| `run` | `--dev-port=<port>`, `-s/--serial`, `--[no-]device-swap`; with `--aera`: `--aerap=<file>`, `--ram` |
| `install` | `-d/--device-id`, `--target=webui\|aera`, `--ram`, `--open`, `--reboot` |
| `logs` | `-d/--device-id`, `--[no-]page` |
| `precache` | `--[no-]web`, `--[no-]webui`, `--[no-]frb`, `--[no-]squadron`, `--[no-]dart-android` (+ `--dart-android-kit`, `--dart-android-sha256`, `--dart-android-abi`), `--[no-]aera` (+ `--aera-mode`, `--aera-kit`, `--aera-kit-sha256`), `--[no-]app-plane` |

`flutter_p0g <command> --help` has the full flag help, including the stock
flags each target inherits; `precache --web` and `precache --webui` are on by
default, everything else is opt-in.

Details: [doc/webui-module.md](doc/webui-module.md) (what `build webui`
assembles), [doc/run.md](doc/run.md), [doc/aera.md](doc/aera.md) (the `.aerap`
format and its install).

What has actually been exercised, so a gap is visible:

| Area | State |
|---|---|
| `build webui`, `build aera` | builds checked end to end (module loads in a headless Chromium with no console errors and no requests outside the module; a debug `.aerap` runs in flutter-aera's host simulator) |
| `run` | works in Chromium (first frame, text, hot reload keeping state); the device path (adb reverse plus page swap) has not run on a phone |
| `run --aera` | checked against a fake adb and a stand-in VM service, not on a device |
| `install` (WebUI) | checked against a fake adb, not on a device |
| `install` (AERA), `logs`, `devices` | not yet run on a device |
| `attach` | not implemented; `run --aera` uses stock `flutter attach` |

## Artifacts

`artifacts.lock.json` at the repository root is the only list of binaries the
stack consumes: for each release, its repository, tag, commit, url, sha256 and
size, all for the Flutter release in `.fvmrc`. `precache` reads it from the
commit this tool runs from; nothing here keeps its own table.

- **Use it.** `flutter_p0g precache --webui` (on by default) resolves the
  WebUI packages from this repository and installs the patched web SDK; the
  locked release when its patch set and engine match, else it builds
  `web_sdk/patches` locally with `web_sdk/tool/build_web_sdk.dart`. Builds
  never touch `<flutter>/bin/cache`; everything lands in
  `<flutter>/bin/cache/flutter_p0g/`.
- **Bump it.** New bytes go to a new release, never over an existing asset.
  Write the new url, sha256 and size here, in one commit, after the release
  exists. The AERA kit and the Android Dart kit add `run:` so the release can
  be traced; local or HTTPS overrides (`--aera-kit`, `--dart-android-kit`)
  always require the matching `--…-sha256`, and installs are staged so a
  failed check leaves the old kit.
- **Publish with the tag.** A package release is the `p0g-v<x.y.z>` tag on a
  commit whose `pkgs/*` all carry that version; the lockstep tag is what
  consumers resolve and what the artifact releases refer to. The release
  workflow and its rules are in
  [.github/docs](https://github.com/p0g-stack/.github/tree/main/docs)
  (`bump.md`).

The web SDK release the lock names is still published by
`p0g-stack/flutter-webui`; future ones come from this repository.

## Patched sources

`precache --frb` builds flutter_rust_bridge from
`third_party/flutter_rust_bridge/PIN` with that series applied, into
`<flutter>/bin/cache/flutter_p0g/frb/`. `precache --squadron` applies
`third_party/squadron` through `squadron_process:squadron_patch` and points
`pubspec_overrides.yaml` at it. `build webui` and `run` do the Squadron step
themselves when nothing overrides `squadron` yet. The series themselves are
maintained with `tool/patches.sh` (see the repository `AGENTS.md`).

## Layout

```
bin/flutter_p0g.dart        entry point
lib/src/executable.dart     command runner inside flutter_tools' context
lib/src/commands/           create, build (web, webui, aera), run, install, devices, logs, precache
lib/src/webui/              module assembly, web SDK + plugin resolution, app plane, workers, cli/
lib/src/aera/               .aerap packer, AERA install and RPC, runtime kits, Rust
lib/src/frb/                pinned flutter_rust_bridge build
lib/src/squadron.dart       patched Squadron for an app
lib/src/artifact_lock.dart  artifacts.lock.json
lib/src/apk/                APK rename and signing (v2), no JDK
test/                       unit tests; tool/web_runtime_proof/ has the browser proofs
tool/resolve.sh             resolve against an SDK (above)
```

## Tests

```sh
pkgs/flutter_p0g_tool/tool/resolve.sh      # from the repository root, once and after the SDK moves
(cd pkgs/flutter_p0g_tool && dart test)    # unit tests; no devices
```

The web runtime proofs (`tool/web_runtime_proof/README.md`) run in a real
Chromium and need `node`; they are not part of `dart test`.
