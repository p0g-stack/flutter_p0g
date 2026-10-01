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

## First packages (proposed)

| Package | Closed by |
|---|---|
| `webui_app_plane` | shared Dart client for `webui-termux-api`: the socket pair and broadcast, about 100 lines |
| `file_selector_webui` | WebView chooser; root listing when a real path is needed |
| `share_plus_webui` | app plane `Share` |
| `url_launcher_webui` | app plane start activity *(new method)* |
| `path_provider_webui` | root channel: module and state dirs |

## Nest (proposed)

```
packages/<plugin>_webui/   one package per plugin, tests against flutter-webui fakes
packages/webui_app_plane/  the app-plane client the others share
docs/plugins.md            route per plugin per host
```

A pub workspace; each package is versioned and published on its own.

## Open

- Registration order: a `*_webui` package and the stock `*_web` package both
  register on web. Whether `*_webui` reliably registers last, or
  `flutter_p0g` has to order the registrant, is unverified.

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
Apps may link these packages, private apps included, without releasing their
own code. Changes to the packages themselves stay LGPL.
