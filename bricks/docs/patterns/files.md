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
