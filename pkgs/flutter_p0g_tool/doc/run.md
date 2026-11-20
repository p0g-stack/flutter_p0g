# `flutter_p0g run`

The app in a WebUI page, with hot reload and hot restart. Run it from the
app's directory.

1. flutter_tools' `web-server` device on a free loopback port, built like
   `build webui` (patched web SDK, the `flutter_webui` plugin, no CDN).
2. A dev server on `--dev-port` (8800) in front of it: CORS for the manager's
   origin (no credentials, `no-store`), the WebUI bootstrap and
   `flutter_webui.js`/`.css`, the fallback fonts, absolute
   `reloaded_sources.json`, and the `Host` header and WebSockets passed
   through.
3. With a device on adb (`-s/--serial`): `adb reverse tcp:8800`, and the
   installed module's `index.html` becomes the WebUI `dev.html` pointed at the
   proxy (the release page kept as `index.release.html` and put back on exit).
   `--no-device-swap` skips this. Without a device, open
   `dev.html?dev=http://127.0.0.1:8800/` from any page that serves the WebUI
   bootstrap.

`q` quits, `r` reloads, `R` restarts, as in `flutter run`.

Devices: checked in headless Chromium with the page on a manager origin
(first frame, text, hot reload keeping state). The device path (adb reverse
plus the page swap) has not been run on a phone yet.

## `flutter_p0g run --aera`

With the device in AERA recovery:

1. builds a debug `.aerap` (`build aera --debug`, or `--aerap <file>`);
2. installs it as `install` does (`--ram` for the RAM store);
3. writes `--vm-service-port` (the stock flag, default 8181) to the plugin's
   `engine-switches` in its data directory (`/sdcard/AERA/plugin-data/<id>`,
   or `/tmp/aera/plugin-data/<id>` when `/sdcard/AERA` is absent, as AERA
   picks it);
4. forwards the port, opens the plugin over AERA's RPC;
5. waits for `vm-service-url` and runs the stock `flutter attach --debug-url
   <url> -d flutter-tester` in the app.

Without a URL in 30 s it prints the tail of `aera-flutter.log`. Checked
against a fake adb and a stand-in VM, not yet on a device.

Opening the plugin needs AERA's Host API 3 patch series (`plugin` operation);
stock AERA answers `unsupported_operation`.
