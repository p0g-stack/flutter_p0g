# A new app, from nothing to a WebUI module

This walks through a p0g app from an empty folder to a module zip that a root
manager (KernelSU, APatch, Magisk with a WebUI host) installs. The example is
named `notes`. Each step says what it produces and how to check it.

## 0. Tools

| Tool | Version | Why |
|---|---|---|
| Flutter | 3.47.9 (Dart 3.13.7) | everything is pinned to it |
| mason_cli | 0.1.4 | the bricks (`dart pub global activate mason_cli 0.1.4`) |
| flutter_p0g | main | `create`, `build webui`, `install` (`dart pub global activate --source git https://github.com/p0g-stack/flutter_p0g`) |
| cargo, cargo-expand | stable | only with `rust: true` |

`~/.pub-cache/bin` must be on `PATH`.

## 1. Generate the workspace

```sh
mason add -g p0g_app --git-url https://github.com/p0g-stack/bricks --git-path bricks/p0g_app
mason add -g service --git-url https://github.com/p0g-stack/bricks --git-path bricks/service
mason add -g strategy --git-url https://github.com/p0g-stack/bricks --git-path bricks/strategy
mason make p0g_app        # name: notes, org: dev.example, rust: false
cd notes
bash tool/bootstrap.sh
```

You now have one pub workspace: `core/` (the logic, plain Dart), `cli/` (the
app's one command line) and `app/` (the Flutter GUI). Bootstrap fetches the
patched Squadron, runs code generation, adds the stock `linux` and `web`
folders to `app/` and compiles the Web Workers. Generated files are not
committed; bootstrap makes them again.

Check:

```sh
dart analyze --fatal-infos
(cd core && dart test) && (cd cli && dart test) && (cd app && flutter test)
dart run cli/bin/notes.dart hello you      # Hello, you!
dart run cli/bin/notes.dart facts          # what this place can do
```

`dart analyze` also runs p0g_lints: Flutter in `core/`, or `kIsWeb` /
`Platform` in a strategy, fails it.

## 2. Add your own service and objective

```sh
mason make service --name notes_store
mason make strategy --name export_notes --strategies '["file", "share"]'
bash tool/bootstrap.sh
```

The service appears in the CLI (`notes notes_store ...`), in `serve` and as a
panel in the app. The objective's strategies start as stubs: list the facts
each needs in `requires`, fill in `run`, and call the objective from a
service method. A device write uses `--write true`, which gives plan,
confirm and receipt. [samples/partition-fetch.md](samples/partition-fetch.md)
is a worked example (on-device `dd` against host `fastboot fetch`).

Keep service methods coarse. A call into the process place costs a few
hundred microseconds, so give each call a whole job and stream progress (see
the service brick's README). Bind work that must keep going while the page
is hidden or rotated to `places.lasting` (the process place) and never to a
Web Worker ([patterns/places.md](patterns/places.md)).

## 3. Run it on a desktop

```sh
(cd app && flutter run -d linux)                              # Squadron place only
dart compile exe cli/bin/notes.dart -o build/notes
(cd app && P0G_CLI=$PWD/../build/notes flutter run -d linux)  # plus the process place
(cd app && flutter run -d chrome)                             # Web Workers
```

With `P0G_CLI` set, the app's Process segment starts `notes serve` and binds
the services there, the same way WebUI will start it as root.

## 4. Add the WebUI target

```sh
cd app
flutter_p0g create .
```

This adds `app/webui/`: `module.prop` (id, name, author; versions come from
`app/pubspec.yaml`), `customize.sh` and `webroot/config.json`. Edit the id
and name now; the id is the module's folder on the device.

Install the kit the CLI needs, once:

```sh
flutter_p0g precache --dart-android    # dartaotruntime + gen_snapshot per ABI
flutter_p0g precache --frb             # only with rust: true
```

## 5. Build the module

```sh
flutter_p0g build webui
```

It runs `flutter build web` against flutter-webui's patched web SDK and adds
the `flutter_webui` web plugin for that build only (the app depends on
`flutter_webui_client` alone). It also compiles the Web Workers and compiles
`cli/` for the device: `bin/notes` (a launcher), `bin/<abi>/notes.aot`,
`bin/<abi>/dartaotruntime`, and with `rust: true` the crate's `.so` beside
them. Output: `build/webui/<id>-v<version>.zip`.

On the device, the page starts `<module>/bin/notes serve` as root through
flutter-webui's root channel and finds it again after a reload
([webui-launch.md](webui-launch.md)). Services bound to the process place
then run as root with the device's facts.

## 6. Install

```sh
flutter_p0g install --reboot     # adb push, then ksud / apd / magisk
```

Open the module's WebUI in the manager. The Process segment's facts should
show `root` and `block_devices`.

## 7. Keep up with the brick

`mason make p0g_app` also writes `tool/p0g_app.json`, the vars the workspace
was made with. Commit it as written; `tool/regen.sh` regenerates the
workspace from it and compares every generated file with yours:

```sh
BRICKS_REF=<full 40-hex bricks commit> bash tool/regen.sh
```

`BRICKS_REF` is required and must be a full commit; anything else exits 64
before fetching. Keep it in your CI environment and your bump instructions,
not in the script, and advance it when you take a new brick version. The
check lists the brick's files before `pub get`, then formats them as
bootstrap does. A file you add is not checked. A generated file must match,
unless it is listed in:

- `tool/regen.allow`: the file may differ or be absent (a replaced README, an
  insertion without a `// p0g:` marker).
- `tool/regen.add`: the file may only gain lines; every generated line must
  still be there, in order (extra dependencies in a pubspec).

Each entry is `<path>  # <reason>` below the files' header comments; the
reason is required. An entry that names no generated file, appears twice or
appears in both files fails the check. Both files are themselves checked as
additions to their generated headers and cannot be listed. Nothing is
overwritten: copy what you want from the brick yourself. Brick CI checks a
local checkout with `bash tool/regen.sh --brick-path <bricks>/bricks/p0g_app`
instead of `BRICKS_REF`.

## Where things stand

- `flutter_p0g run` (hot reload on WebUI) works in Chromium; its device path
  (adb reverse, page swap) has not been run on a device. See flutter_p0g's
  README for its current state.
- The Android Dart kit that step 4 installs is flutter_p0g's release
  `dart-android-<Dart version>`. It is fetched by tag; its sha256 is checked
  only when passed to `precache` (flutter_p0g `PINS.md`).
- Rust on the page needs flutter_p0g's patched frb (`precache --frb`). Without
  it, `tool/rust.sh` builds only the native library, and on the web the
  Dart strategies run.
