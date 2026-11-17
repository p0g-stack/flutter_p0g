# Patterns: saving a file

Apps pick a place to save with the stock `file_selector`
`getSaveLocation`. flutter_p0g adds `file_selector_webui` to WebUI builds,
which shows a root folder picker. What the app does with the path it gets
back depends on where it runs.

| Where | Write it with |
|---|---|
| Desktop, AERA, CLI | `dart:io` (`File(path).writeAsBytes`) |
| WebUI, bytes made in the process place | `dart:io` in the process place, which is root. Send the path, not the bytes. |
| WebUI, bytes made in the page | `WebUiRoot.writeFile(path, bytes)` from `webui_app_plane` (webui-packages). It writes `<path>.part` as root, then renames it. |
| Browser tab | `XFile.fromData(bytes).saveTo(path)`, which downloads the file |

On WebUI, after writing into shared storage (`Download`, `Documents`, any
path from the picker), call `AppPlane.scanMedia([path])` so the file shows
up in Files and Gallery. Files written as root aren't indexed on their own.

Don't call `XFile.saveTo` on WebUI. That method belongs to `cross_file`, so
no plugin can redirect it. On web it starts a download, and no manager
handles downloads, so nothing happens.

The bricks don't depend on webui-packages. An app that saves files adds
`webui_app_plane` itself, at the commit flutter_p0g builds with. Big files
should never pass through the page: make and write them in the process
place.

## Pickers on embedded hosts

App code calls only the stock federated `file_selector` API: `openFile`,
`openFiles`, `getDirectoryPath`, `getSaveLocation`. Each embedding implements
that API with the host's own picker, because an embedded platform has its own
style and its users expect its picker, not one the app brings along.

When the host picker lacks a mode, the embedding does one of these, in this
order:

1. Extend the host picker with that mode, shaped the way the host's own API
   is shaped and behind a negotiated feature flag, so it can go upstream.
2. Until that lands, return a clear "unsupported" for that mode. Never fake
   it: no single file returned for `openFiles`, no guessed save path.

An app-drawn picker is the last resort. Use it only when the host can't be
extended at all, and then match the host's look.

| Host | Native modes | Missing, and the plan |
|---|---|---|
| WebUI (KernelSU manager, WebUI X) | file, files, folder, save through `file_selector_webui` (root folder picker) | none |
| AERA, current protocol (Host API 3 fork) | file, files, folder, save | none |
| AERA on upstream Host API 2 (deferred migration) | file, folder (`PickFile`) | files and save: one more recovery patch adds multi-select and a save-name mode behind a new feature bit |
| Browser tab | the browser's dialogs | save is a download (see above) |
