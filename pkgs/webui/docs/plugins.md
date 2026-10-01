# Plugins: route per plugin per host

Each `*_webui` package takes the first route that works on every manager
(README, "How a plugin is closed"). Host behaviour comes from
`WebUiHost.detect` in `flutter_webui_client` (pinned at flutter-webui
`3049dc9`), never a manager name. In a browser tab every package hands
everything to the stock web implementation, so one web build serves both.

**Nothing below is device-verified.** Routes are chosen from source reads;
"works" claims come from devicelab runs, named by device and manager, when
they exist. Open device checks are listed per plugin.

## Registration (resolved)

Flutter registers **one** web implementation per app-facing plugin, not all of
them in some order. flutter_tools 3.47.5 runs web plugins through
`_resolvePluginImplementationsByPlatform` and
`_resolveImplementationOfPlugin` (`packages/flutter_tools/lib/src/flutter_plugins.dart`)
before writing `web_plugin_registrant.dart`. The rules there, checked by
building a sample app with `flutter build web`:

| How the app gets `*_webui` | file_selector, url_launcher (endorsed `*_web`) | share_plus (web inline in `share_plus`) | path_provider (no web) |
|---|---|---|---|
| direct dependency | `*_webui` registered, `*_web` not | `share_plus_webui` registered, `share_plus`'s web class not | `path_provider_webui` |
| only transitive | build fails: "has multiple possible implementations" | stock `share_plus` web silently wins | `path_provider_webui` |

So registrant order never needs forcing, but **flutter_p0g's WebUI build must
add every `*_webui` package the app's plugins have as a direct dependency**,
as it adds `flutter_webui` (for example the generated pubspec overlay or
`dependency_overrides` plus `dependencies` entries; a path or git dependency
is enough). An app that also builds a plain browser target can keep them:
each package falls back to stock in a browser tab.

Because the stock web package is then not registered, each `*_webui`
`registerWith` builds the stock implementation itself and delegates to it
(`url_launcher_webui` calls `UrlLauncherPlugin.registerWith` first, which also
registers the `Link` platform view).

## Shared pieces (`webui_app_plane`)

- `WebUiRoot`: the host plus root commands through the root channel
  (`run(argv, stdin)`, `sh(script, args)`; values are always argv, never
  spliced into a script).
- `AppPlane`: the module's own copy of webui-termux-api from the page,
  renamed per module to `com.webui.api.<seg>` (`appPlanePackage`: the module
  id with characters outside `[A-Za-z0-9_]` as `_`, `m` prefix before a digit;
  webui-termux-api WEBUI.md, "Renaming per module"). Pre-check `pm path
  <package>` (once), which also runs `appops set
  com.webui.termux.api SYSTEM_ALERT_WINDOW allow`: methods that open an
  activity from the broadcast (Share's chooser) are otherwise blocked as
  background activity starts on Android 10+ (devicelab: "Background activity
  launch blocked!" without it, chooser shown with it). A call runs
  `<moddir>/webui_app_plane/termux-api [--package P] <Method> [extras]` as an
  attached root process; that launcher runs `bin/webui_termux_api.dart`, the
  Dart port of termux-api from termux-api-package 9e7f153 (`run_api_command`,
  `exec_am_broadcast_v2`): two abstract AF_UNIX sockets, `am broadcast --user 0
  -n com.webui.termux.api/com.termux.api.TermuxApiReceiver --es socket_input
  ... --es socket_output ... --ei api_server_pid/uid/starttime --es
  api_method <Method>`, stdin to the app, the app's answer to stdout
  (webui-termux-api `util/ResultReturner.java`). The same library
  (`package:webui_app_plane/termux_api.dart`) can run inside an app's own
  root process.
- `handoff()`: methods that read or write a `file` extra open it as the
  app's uid, so each call gets its own folder
  `/data/data/<package>/cache/handoff/<call id>/`; `AppHandoff.write` puts a
  file there chowned to the app and `chcon`ed to the app data dir's full
  context (`restorecon` leaves `s0` without the app's MLS categories,
  devicelab, Android 15 AVD), and `delete` removes the folder after the call.
  Separate folders mean no stale picks and no two calls wiping each other.
  The first hand-off of a page removes what earlier pages left; Android may
  also reclaim the cache dir.
- `scanMedia(paths)`: after the app writes a file to shared storage
  (`Download`, `Documents`, a path from the save picker), asks the media
  provider to index it so it shows in Files and Gallery: a root
  `MEDIA_SCANNER_SCAN_FILE` broadcast per file (devicelab, Android 15: indexed;
  files written as root are not indexed on their own). The app's
  `MediaScanner` method is gone since webui.3. No `*_webui` package writes
  to shared storage itself (`share_plus_webui` writes only into a hand-off
  folder), so the app, or bricks' save flow, calls it after its
  write.
- `testing.dart`: `FakeRootChannel` speaks the real v1 protocol to the real
  `RootChannel` client; plugin tests script its processes. The Termux:API
  client is tested against a fake app on real abstract sockets.

App: release `webui-v0.53.0-webui.3` of p0g-stack/webui-termux-api
(7c75e03, versionCode 1005), `webui-termux-api_v0.53.0-webui.3.apk`, sha256
`442d227d839e936b9c635b48991c5bf393870d382d689971eba4fdfe88bebeb1`, package
`com.webui.termux.api`, test key. flutter_p0g renames it per module to
`com.webui.api.<seg>` and signs it with the developer's key; the app takes
its socket, share authority and intents from `getPackageName()` (see its
`WEBUI.md`: webui.3 drops `JobScheduler`, webui.2 dropped SMS, contacts, call
log and telephony).

### What flutter_p0g ships for the app plane

When an app depends on `webui_app_plane` (directly or through a plugin):

```
<moddir>/webui_app_plane/termux-api                     packages/webui_app_plane/module/termux-api
<moddir>/webui_app_plane/<abi>/webui_termux_api.aot     AOT snapshot of bin/webui_termux_api.dart
system/product/app/WebuiApi_<seg>/WebuiApi_<seg>.apk   the release APK above, renamed to the module's package and re-signed
```

The launcher reuses flutter-webui's runtime in `<moddir>/flutter_webui/<abi>/`
(and its glibc loader when present), exactly as `flutter_webui/root` does.

## Per plugin

Hosts: **KSU** KernelSU, SukiSU; **Next** KernelSU Next, APatch; **SA**
KsuWebUIStandalone; **WX** WebUI X Portable, MMRL. All have `ksu.exec`, so
all have the root channel (APatch finds its module id from the build's
`<meta name="webui-module-id">`).

### file_selector_webui

| Method | All WebUI hosts | Browser tab |
|---|---|---|
| `openFile`, `openFiles` | stock web: `<input type=file>`; every manager implements `onShowFileChooser` | stock |
| `getDirectoryPath(s)`, `...WithOptions` | root listing picker (one directory) | stock (`null`) |
| `getSaveLocation`, `getSavePath` | root listing picker plus a file name | stock (`''`) |

The picker is a DOM overlay (as `file_selector_web` uses a DOM input), driven
by `PickerState` over `ls -1ApL -- <dir>` as root (directories first; symlinks
to directories count as directories). It starts at `initialDirectory` or
`/storage/emulated/0` and walks up past unreadable directories. An unreachable
root channel is `PlatformException(webui-root-unavailable)`.

Gaps: the returned paths are real root paths, so the app reads or writes them
through its root process or the root channel; `XFile.saveTo` on web still
downloads, and no manager sets a WebView `DownloadListener` (source read), so
saving bytes from the page needs the activity-results/save work, not this
plugin. After writing to the returned path, call
`AppPlane.scanMedia([path])` so the file shows in Files and Gallery. Open device checks: chooser accept filters per manager; toybox `ls
-1ApL` output on Android 10 to 15.

### path_provider_webui

No stock web implementation, so this registers even when transitive.

| Method | WebUI host | Browser tab |
|---|---|---|
| temporary | `/data/adb/<id>/tmp` (created) | stock (`MissingPluginException`) |
| application support | `/data/adb/<id>` (created, 700) | stock |
| application cache | `/data/adb/<id>/cache` (created) | stock |
| documents | `/data/adb/<id>/documents` (created; private, as on Android) | stock |
| downloads | `/storage/emulated/0/Download` | stock |
| library, external storage | unimplemented, as `path_provider_linux` | unimplemented |

State is outside `/data/adb/modules/<id>` because a module update replaces
that directory. Lifetimes follow KernelSU's module lifecycle (kept by
flutter_p0g's customize.sh and flutter-webui's root launcher): a fresh
install starts with an empty `/data/adb/<id>` (install marker
`webui.installed` in module config), temp is cleared on the first start of
each boot, uninstall.sh removes the folder. The paths are for the app's root
process; the page cannot open them.

### shared_preferences_webui

`SharedPreferences`, `SharedPreferencesAsync` and `SharedPreferencesWithCache`
keep a module's preferences as one JSON object in KernelSU's module config:
`KSU_MODULE=<id> /data/adb/ksu/bin/ksud module config set
webui.shared_preferences --stdin` (persist.config, KernelSU and KernelSU Next
since v3.0.0). ksud keeps it across updates and while the module is
disabled, and clears it on uninstall. Every operation reads it fresh; a
change writes it whole, one at a time per page. Values are the stock web
types (bool, int, double, String, `List<String>`); the whole object may be
at most 1 MB (ksud's limit per value), else
`PlatformException(webui-prefs-too-large)`. Why not localStorage: every
module page shares one origin, so `flutter.` keys of different modules clash
and `clear()` would wipe them all. A browser tab keeps the stock
localStorage store.

Gaps: a `Link` widget on KSU/Next still navigates the WebView (stock link
delegate). Open device checks: `am start` and `cmd package query-activities
--brief` output per Android version.

### share_plus_webui

| Case | WebUI host with the app | No app / browser tab |
|---|---|---|
| text or `uri` | `Share`, text on stdin, `--es action send`, `--es title <subject>` | stock: no `navigator.share` in WebViews, so `mailto:` through url_launcher_webui |
| one file | copied into a hand-off folder (kept: the target reads it after Share returns), `Share --es file <path> --es action send [--es content-type]` | stock download (does nothing in a manager) |
| more than one file | `PlatformException(webui-share-multiple-files)` | stock |

Result is `ShareResult.unavailable` (ShareAPI reports no outcome; as Linux).
ShareAPI prints its errors to stdout; those become
`PlatformException(webui-share-failed)`. `ShareParams.title` (chooser title)
is not supported by ShareAPI. Fork gaps: `ACTION_SEND_MULTIPLE`, text with a
file.

Devicelab (Android 15 x86_64 AVD, SELinux enforcing, KernelSU 3.3.0
jailbreak mode; devicelab `lab-results`
`runs/20261001T092147Z-avd-ksu-kernelsu-36841013518/app-plane.jsonl`):
- a root `am broadcast -n com.webui.termux.api/com.termux.api.TermuxApiReceiver`
  with the termux-api extras starts the app (`untrusted_app_27`) and
  `BatteryStatus` answers;
- the app connects to abstract sockets bound by a `u:r:su:s0` root process
  with no AVC denials (the root channel's own `u:r:ksu:s0` domain not yet
  tried);
- placing the APK as a system app on KernelSU needs the module to mount
  `/product/app` itself (Magisk-style rbind of a tmpfs) or a metamodule;
  that is flutter_p0g's module template.

- `Share` works end to end (text, and one `chcon`ed file with targets
  listed) once the appop is granted; the file passed ShareAPI's own
  readability check as the app (devicelab
  `runs/20261001T111144Z-avd-ksu-kernelsu-demo-0.9-final-2-36852361631`).

### dynamic_color_webui

`dynamic_color` (2.1.0) has no web implementation and is not federated: it
calls `OptionalMethodChannel('io.material.plugins/dynamic_color')` and treats
`null` as "no dynamic colour". This package answers that channel on a WebUI
host, so apps keep `DynamicColorBuilder` / `DynamicColorPlugin` unchanged.

| Method | WebUI host with colours | Host without colours / browser tab |
|---|---|---|
| `getCorePalette` | 5 x 13 tones built from the host's `primary`, `secondary`, `tertiary`, `surfaceVariant` | `null` |
| `getAccentColor` | the host's `primary` | `null` |

Colours come from the page-side virtual stylesheet `/internal/colors.css`
(`:root { --<role>: #rrggbb[aa]; }`, Compose ColorScheme role names), fetched
once:
- KernelSU (08a3b08, `SuFilePathHandler` + `MonetColorsProvider`): filled only
  in its Monet colour modes or the Material UI mode, otherwise empty, so the
  app keeps its own scheme.
- WebUI X (ed569e1, `InternalPathHandler` + `WebColors`, also under
  `/mmrl/`): always filled, `#rrggbbaa`.
- APatch, KernelSU Next, KsuWebUIStandalone: not checked; a missing or empty
  stylesheet answers `null`.

Both managers serve **one** scheme, the manager's current light or dark one,
with every Compose Material 3 role (36 roles, no fixed roles; table in the
project research note `research/webuix-enhancements.md`). The CorePalette is
rebuilt per family: the key role's hue and the highest chroma among the
family's roles (`primary`, `primaryContainer`, `onPrimaryContainer`,
`inversePrimary`; the same for secondary and tertiary; neutrals from
`inverseSurface`, `onSurface`, `inverseOnSurface`; neutral variant from
`onSurfaceVariant`, `outline`, `outlineVariant`, `surfaceVariant`). From a
full Tonal Spot set, the scheme rebuilt for the *other* brightness lands
within a few HCT units of the real one (tests, four seeds). KernelSU's MIUIX
UI mode fills some roles with other colours (`tertiary` is a container
variant, `surfaceDim` is `surface`, ...); that shape is detected and those
roles are ignored.

Through the stock API every role is derived from the palette, as on Android
(`CorePaletteToColorScheme`), so light and dark are both complete and the
app picks one by its own brightness. Beyond the stock API,
`DynamicColorWebUi.hostColorScheme(brightness)` returns a Flutter
`ColorScheme` with the manager's exact colours for every role it serves when
the stylesheet has that brightness (tone of `background`), the rest derived.
The other brightness is fully derived, so a page whose brightness differs
from the manager's (KernelSU's forced dark on a light system) never gets the
wrong set.

Checked in headless Chromium with a stub `window.ksu` and a served
`internal/colors.css`: `DynamicColorBuilder` got primary `#4a6800`; in a
plain tab it got `null`. Not yet device-verified per manager.

Note for apps: `dynamic_color` 2.1.0 hands back `package:material_ui`'s
`ColorScheme`, not `package:flutter/material.dart`'s, so it cannot go straight
into `ThemeData(colorScheme:)`; that is the stock package's API, unchanged
here. Like the others, this package must be a direct dependency of the WebUI
build (flutter_p0g adds it).
