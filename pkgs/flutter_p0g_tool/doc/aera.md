# AERA: the `.aerap` and its install

`flutter_p0g build aera` produces `build/aera/<id>-<version>.aerap` and a copy
of `plugin.json`, following flutter-aera's `spec/aerap.md`.

- `flutter build bundle` for linux-arm64; any `build bundle` flag works. Debug
  keeps `kernel_blob.bin` for a debug (JIT) engine; profile and release add
  `usr/lib/libapp.so` from the SDK's frontend server plus the kit's
  `gen_snapshot`.
- The app's `flutter_assets` and the runtime kit's tree become AERA's runtime
  stream, xz-compressed with CRC32 and the ARM64 BCJ filter (XZ Utils 5.4+).
- `plugin.json` is the app's `aera/plugin.json` plus the packer's fixed and
  computed fields. `--payload-url` names where `runtime.xz` will be published
  (any HTTPS URL for a local install).
- A `padding` object in `aera/plugin.json` (`{"left":4,"top":0,"right":4,
  "bottom":8}` in dp, any edge optional) becomes `usr/share/flutter/view.json`,
  the app's default for flutter-aera's per-edge padding; without it no file is
  written.
- With `rust/Cargo.toml` (in the app or the workspace root) the crate is
  cross-built for `aarch64-unknown-linux-gnu` and every `*.so` goes into
  `usr/lib/`, where the kit's loader finds it by bare name. Needs
  `rustup target add aarch64-unknown-linux-gnu` and `aarch64-linux-gnu-gcc`
  (or `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER`). `--no-device-rust`
  ships without it.

## The runtime kit

`flutter_p0g precache --aera [--aera-mode=debug]` selects the exact url and
sha256 from `artifacts.lock.json`; an unsupported version or mode fails rather
than guessing a release. `--aera-kit=<path|url>` requires
`--aera-kit-sha256=<64-hex>`, including for local archives. The cache is
replaced only after verification and extraction succeed, with a complete
identity file. The kit's `kit.json` must name the pinned engine revision and
stays out of the payload, as does `host/gen_snapshot`, which profile and
release kits need (only a debug kit is released so far).

## Install

With the device in AERA recovery (adb runs as root there), `install` does what
AERA's Plugin Manager does for a local `.aerap`: it checks the package, pushes
`plugin.json`, `runtime.xz` and the signature if there is one, stages them,
checks the payload's sha256, makes the files 0444, and renames the staging
directory to `/sdcard/AERA/plugins/<id>` (`--ram`: `/tmp/aera/plugins/<id>`).
A previous install is kept until that rename succeeds. Installing this way
skips the manager's "unofficial plugin" prompt, as `adb install` skips
Android's.

`--open` sends `{"v":1,"op":"plugin","args":{"action":"open","id":…}}` to
AERA's RPC FIFOs after the install.
