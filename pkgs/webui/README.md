# webui-packages

Plugin implementations for the WebUI platform (`flutter-webui`): one
`<plugin>_webui` package per stock plugin, so an app keeps calling
`url_launcher`, `file_selector`, `share_plus` and the rest unchanged. The same
layout as flutter-pi's `flutter_packages`.

## How a plugin is closed

Each package picks the first route that works on every manager, and improves
on it where a host offers more. Hosts are detected by `flutter_webui`, never by
manager name.

| Route | What it is |
|---|---|
| web | the stock web implementation already works in the WebView; no package needed |
| root channel | `flutter_webui`'s root channel: shell commands and files as root |
| app plane | `webui-termux-api` (repackaged Termux:API placed by the module), driven over the root channel |
| WebUI X | WebUI X bridge additions, as an improvement only |

Which route each plugin uses, per host, lives in `docs/plugins.md`. A plugin
with no route on the baseline is not shipped as a stub.

## Packages

| Package | Closed by |
|---|---|
| `webui_app_plane` | shared pieces: root commands, the `webui-termux-api` client (the socket pair and broadcast) and its pre-check, test fakes |
| `file_selector_webui` | WebView chooser for files; root listing picker for directories and save locations |
| `share_plus_webui` | app plane `Share` |
| `url_launcher_webui` | root channel: `am start` VIEW (no new app method needed) |
| `path_provider_webui` | root channel: `/data/adb/<id>` state, shared storage dirs |

## Nest

```
packages/<plugin>_webui/   one package per plugin, tests against flutter-webui fakes
packages/webui_app_plane/  the app-plane client the others share
docs/plugins.md            route per plugin per host
```

A pub workspace; each package is versioned and published on its own.

## Registration

Flutter registers one web implementation per plugin; a `*_webui` package
replaces the stock one only as a **direct** dependency of the app (as a
transitive one the build fails, or for share_plus the stock one wins). So
`flutter_p0g`'s WebUI build adds the `*_webui` packages as direct
dependencies; no registrant ordering is involved. Details in
`docs/plugins.md`.

## Tests

`dart test` in `packages/webui_app_plane`, `flutter test` in each plugin.
Unit tests only, against `webui_app_plane/testing.dart` (a fake root channel
speaking the real protocol) and a fake Termux:API app on real abstract
sockets; host claims come from devicelab.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
Apps may link these packages, private apps included, without releasing their
own code. Changes to the packages themselves stay LGPL.
