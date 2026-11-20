# What `flutter_p0g build webui` assembles

Stock `flutter build web`, WebUI defaults, then a KernelSU-style module zip.
Every `flutter build web` flag works; two defaults differ: CanvasKit and the
fonts are bundled (`--no-web-resources-cdn`; a manager may have no CDN) and no
service worker is registered (no manager runs one).

1. **Rust, if the app has `flutter_rust_bridge.yaml`**: the patched
   flutter_rust_bridge's `build-web --no-threads` into `web/pkg/`. The wasm is
   single-threaded, so it runs without COOP/COEP headers.
2. **The patched web SDK and the WebUI packages**: `precache --webui` (also
   run on first use) resolves `pkgs/flutter_webui`,
   `pkgs/flutter_webui_client`, `pkgs/flutter_webui_root`, `web_sdk` and every
   `pkgs/webui/*` package by path into
   `<flutter>/bin/cache/flutter_p0g/webui-sources`, and installs the patched
   web SDK into `<flutter>/bin/cache/flutter_p0g` (so `bin/cache` stays
   stock). The SDK comes from the release in `artifacts.lock.json` when its
   patch set and engine match, else from `web_sdk/patches` built locally.
   `flutter build web` compiles against it, and the WebUI bootstrap replaces
   the page: `index.html` with the module id and name, a filled
   `flutter_bootstrap.js`, `flutter_webui.js` and `flutter_webui.css`.
3. **The web plugin.** Apps depend on `flutter_webui_client` alone; the build
   adds the `flutter_webui` web plugin for itself, so `FlutterWebUi.registerWith`
   runs before the app's `main()` (as flutter-tizen registers its embedding
   plugins). Packages the app already resolves stay its own.
4. **The `*_webui` implementations.** For each plugin the app uses that
   `pkgs/webui` implements, the build makes that package a **direct**
   dependency for the build only: Flutter registers one web implementation per
   plugin, and the `*_webui` one wins only as a direct dependency. The package
   config, the package graph and the manifest flutter_tools sees carry it
   while the build runs; `pubspec.yaml` and the lock file are not touched.
5. **Pruning.** `*.symbols`, the service worker, `webparagraph/`, `wimp.*` and
   Skwasm (unless `--wasm`) are removed: a manager never loads them.
6. **Workers.** Every generated `*.web.g.dart` in the app or its workspace
   packages is compiled (`dart compile js`, `wasm` with `--wasm`) to the
   `~/workers/...` path its activator loads, inside `webroot/`.
7. **Fonts.** `web_ui`'s fallback fonts (Roboto, Noto Sans, emoji, symbols,
   math; fetched once with the SDK) go to `webroot/fonts/` and the bootstrap
   points the engine there: a manager WebView has no system fonts.
8. **The root channel.** `flutter_webui/root` and, per ABI,
   `flutter_webui/<abi>/{flutter_webui_root.aot,dartaotruntime}`, compiled as
   below. `customize.sh` gets a generated block making the tool's program
   directories executable.
9. **Module data.** `/data/adb/<id>/` is the app's support, documents, cache
   and temp directory. `customize.sh` gains a block that removes a leftover
   `/data/adb/<id>` on a fresh install, keeps it on an update, and sets
   `webui.installed` in KernelSU's `ksud module config`. `uninstall.sh` ends
   with `MODPATH=${0%/*}; rm -rf "/data/adb/${MODPATH##*/}"`, after the app's
   own `webui/uninstall.sh` if it has one.
10. **The app plane**, when `webui_app_plane` is in the build (a `*_webui`
    plugin brings it): `webui_app_plane/termux-api`,
    `webui_app_plane/<abi>/webui_termux_api.aot`, and the module's own copy of
    the webui-termux-api APK. The APK is renamed to `com.webui.api.<seg>`
    (`<seg>`: the module id, characters outside `[A-Za-z0-9_]` turned into
    `_`, `m` in front of a leading digit), labelled with `module.prop`'s
    name, and re-signed (APK Signature Scheme v2, no JDK) with
    `android/key.properties` if present, else the debug key. **Releases need a
    stable key**: Android keeps grants and data only while the signing key
    stays the same, and debug keys differ per machine. A CI that publishes
    modules writes `android/key.properties` and the keystore from its
    secrets. Never put keys in `webui/`: the build leaves out
    `key.properties` and `*.jks` / `*.keystore` / `*.p12` / `*.pfx` found
    there, and warns.
    The app is **installed, not mounted**: KernelSU's per-app "Unmount
    modules" would take a mounted APK away from its own process. The build
    writes `webui_app_plane/app-install.sh`, which installs the APK through a
    PackageInstaller session (as the Play Store does), temporarily disabling
    the package verifier and restoring it even on failure. `customize.sh` runs
    it on every install and update; `service.sh` with `--if-missing` after boot;
    `uninstall.sh` uninstalls the package.
11. **The root process** (`cli/`, the bricks layout). Stock Dart cannot target
    Android from a desktop host, and an AOT snapshot loads only in a runtime of
    its own Dart version, OS and flags. So `--cli-format=aot` (the default)
    compiles `cli/` to AOT kernel with the SDK's `gen_kernel --aot
    --target-os android`, turns it into an android-arm64 ELF with the kit's
    `gen_snapshot`, and ships `bin/<abi>/<name>.aot`,
    `bin/<abi>/dartaotruntime` and `bin/<name>`, a launcher that picks the
    device ABI and sets `TMPDIR` (a root shell may start empty). The kit comes
    from `artifacts.lock.json` (`precache --dart-android`, one per ABI).
    `--device-rust` cross-builds `rust/` beside it; `--device-rust-libs=<dir>`
    takes libraries built elsewhere (`<dir>/<abi>/*.so`).
12. **Zip.** The web build in `webroot/`, `webui/` on top (its own `webroot/`
    overlays), Magisk's installer stub in `META-INF/`. `module.prop`'s
    `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` come from the pubspec
    version or `--build-name` / `--build-number`.
13. **Self-update.** `updateJson` in `module.prop`, plus `update.json` and
    `changelog.md` beside the zip (the format KernelSU, APatch and Magisk
    poll), so the manager's update button works once a release publishes all
    three. They go under `--update-url`, else the directory of an `updateJson`
    already in `webui/module.prop`, else `releases/latest/download/` of the
    pubspec's GitHub repository. With none of those, or `--no-update-json`,
    the module has no `updateJson`.

Output: `build/webui/<id>-v<version>.zip`.
