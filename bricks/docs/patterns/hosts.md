# Patterns: host affordances

An embedded platform has its own style and its users' preferences. A p0g app
therefore uses each host's own affordances, not copies the app draws itself.
This applies to every capability: pickers, keyboard and text input, Back and
navigation, clipboard, notifications, background services, theme and insets.

## The rule

App code calls the standard Flutter or federated-plugin API for a capability:
`file_selector`, `TextInput`, `SystemNavigator`/`PopScope`, `Clipboard`,
`flutter_local_notifications`, `MediaQuery` insets and brightness, or a
Squadron service. Each embedding (flutter-webui, flutter-aera, the browser)
implements that API with the host's native affordance.

When a host lacks something the API needs, the embedding does one of these, in
this order:

1. Extend the host. Shape the addition the way the host's own API is shaped,
   put it behind a negotiated feature flag numbered after the host's own, and
   prepare it for upstream.
2. Until that lands, report a clear "unsupported" for that case. Never fake
   it: no single file for a multi-pick, no guessed keyboard height, no Back
   that does nothing.

App-drawn replacements (an in-app picker, an on-screen keyboard, a
notification banner) are the last resort. Use one only for a host that can't
be extended at all, and then match the host's look.

Each embedding follows the newest host release (the dependency policy). When a
host changes its interface, the embedding moves to the new one and drops the
old path. It never keeps both.

## Where each capability comes from

| Capability | WebUI (KernelSU manager, WebUI X) | AERA, current protocol (Host API 3 fork) | AERA on upstream Host API 2 (deferred migration) | Browser tab |
|---|---|---|---|---|
| Files | root folder picker through `file_selector_webui` ([files.md](files.md)) | native picker: file, files, folder, save | native `PickFile`: file, folder. Files and save: planned recovery patch | browser dialogs; save is a download |
| Keyboard, text | Android IME in the webview; keyboard height reported by the host | host keyboard with show/hide and inset | desktop keyboard, extended by the bit 12 patch (show/hide, inset, Unicode); native field editor via bit 13 | browser IME |
| Back | host Back into `SystemNavigator`/`PopScope` | host Back | desktop ESC into Flutter Back; system Back not guaranteed | browser history |
| Clipboard | host clipboard (flutter-webui) | host clipboard | upstream clipboard kinds 22–24; shared clipboard not yet wired | browser clipboard |
| Notifications | Android's own prompt and notifications through webui-termux-api | none | none | browser notifications |
| Background work | process place (root) via squadron_process; Termux:API foreground dispatch | in-plugin workers | upstream background tasks; not used yet | web workers |
| Theme, insets | host brightness and insets (flutter-webui web_ui patches) | host surface size and insets | desktop size; no live resize or rotation yet | browser |

Rows marked "not yet" or "planned" are open work. Fill each one by following
the rule above.
