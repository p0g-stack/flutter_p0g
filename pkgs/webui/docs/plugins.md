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
- `AppPlane`: webui-termux-api from the page. Pre-check `pm path
  com.webui.termux.api` (once), which also runs `appops set
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
- `writeAppFile`: methods that read a `file` extra open it as the app's uid,
  so files go to `/data/data/com.webui.termux.api/files/<moduleId>/`, chowned
  to the app and `chcon`ed to the app data dir's full context (earlier files
  there are removed first). `restorecon` is not enough: it leaves `s0`
  without the app's MLS categories (devicelab, Android 15 AVD).
- `scanMedia(paths)`: after the app writes a file to shared storage
  (`Download`, `Documents`, a path from the save picker), asks the media
  provider to index it so it shows in Files and Gallery. With the app it is
  Termux:API `MediaScanner` (`--esa paths`); without it, a root
  `MEDIA_SCANNER_SCAN_FILE` broadcast per file. No `*_webui` package writes
  to shared storage itself (`share_plus_webui` writes only into the app's
  private directory), so the app, or bricks' save flow, calls it after its
  write. Not device-verified: whether MediaProvider indexes a file through
  either route on Android 10 to 15.
- `testing.dart`: `FakeRootChannel` speaks the real v1 protocol to the real
  `RootChannel` client; plugin tests script its processes. The Termux:API
  client is tested against a fake app on real abstract sockets.

App: release `webui-v0.53.0-webui.1` of p0g-stack/webui-termux-api,
`webui-termux-api_v0.53.0-webui.1.apk`, sha256
`bd0d1153d1d12eef08d3539a7dcd5ec9fc45b96dfc48b55eb6b29d57bcd9537e`, test key
(see its `WEBUI.md`).

### What flutter_p0g ships for the app plane

When an app depends on `webui_app_plane` (directly or through a plugin):

```
<moddir>/webui_app_plane/termux-api                     packages/webui_app_plane/module/termux-api
<moddir>/webui_app_plane/<abi>/webui_termux_api.aot     AOT snapshot of bin/webui_termux_api.dart
system/product/app/WebuiTermuxApi/WebuiTermuxApi.apk    the release APK above, pinned by sha256
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
| temporary | `/data/local/tmp` | stock (`MissingPluginException`) |
| application support | `/data/adb/<id>` (created, 700) | stock |
| application cache | `/data/adb/<id>/cache` (created) | stock |
| documents | `/storage/emulated/0/Documents` | stock |
| downloads | `/storage/emulated/0/Download` | stock |
| library, external storage | unimplemented, as `path_provider_linux` | unimplemented |

Shaped like `path_provider_linux`. State is outside `/data/adb/modules/<id>`
because a module update replaces that directory; flutter_p0g's module
template `uninstall.sh` should remove `/data/adb/<id>`. The paths are for the
app's root process; the page cannot open them.

### url_launcher_webui

| Method | WebUI host | Browser tab |
|---|---|---|
| `launchUrl` | `am start --user current -a android.intent.action.VIEW -d <url>` as root; `false` when `am` reports `Error:` | stock (`window.open`) |
| `canLaunch` | `cmd package query-activities --brief -a VIEW -d <url>` finds an activity | stock |
| `supportsMode` | `platformDefault`, `externalApplication` | stock |
| `Link` widget | stock | stock |

Why not stock on a host: the managers do not support multiple windows, so
`window.open` loads the URL in the module's WebView. KernelSU and Next then
navigate the page away; WebUI X opens non-module URLs externally
(`WXClient.shouldOverrideUrlLoading`), so it would work there alone. Why not
an app-plane method (the README's first proposal): root may start activities
(uid 0 is exempt from background activity start limits in AOSP
`BackgroundActivityStartController`, inferred), so the fork needs no new
method. `javascript:` is refused as in stock.

Gaps: a `Link` widget on KSU/Next still navigates the WebView (stock link
delegate). Open device checks: `am start` and `cmd package query-activities
--brief` output per Android version.

### share_plus_webui

| Case | WebUI host with the app | No app / browser tab |
|---|---|---|
| text or `uri` | `Share`, text on stdin, `--es action send`, `--es title <subject>` | stock: no `navigator.share` in WebViews, so `mailto:` through url_launcher_webui |
| one file | copied by `writeAppFile`, `Share --es file <path> --es action send [--es content-type]` | stock download (does nothing in a manager) |
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

Primary keeps its hue with chroma at least 48 (as Material's `CorePalette`);
secondary and tertiary keep the host's own hue and chroma; neutrals use
`surfaceVariant`'s hue with chroma 4 and 8. Missing roles fall back to
`CorePalette.of(primary)`.

Checked in headless Chromium with a stub `window.ksu` and a served
`internal/colors.css`: `DynamicColorBuilder` got primary `#4a6800`; in a
plain tab it got `null`. Not yet device-verified per manager.

Note for apps: `dynamic_color` 2.1.0 hands back `package:material_ui`'s
`ColorScheme`, not `package:flutter/material.dart`'s, so it cannot go straight
into `ThemeData(colorScheme:)`; that is the stock package's API, unchanged
here. Like the others, this package must be a direct dependency of the WebUI
build (flutter_p0g adds it).
