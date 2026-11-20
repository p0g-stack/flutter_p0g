# flutter_p0g

The command line that takes a stock Flutter app to the two p0g targets:

```sh
flutter_p0g create .            # adds webui/ and aera/ (and web/ if missing)
flutter_p0g build webui         # build/webui/<id>-v<version>.zip
flutter_p0g install --reboot    # adb push, then ksud / apd / magisk
flutter_p0g logs                # the module's root process and page console

flutter_p0g build aera          # build/aera/<id>-<version>.aerap
flutter_p0g install --open      # into AERA recovery's plugin store, then open it
```

`flutter_p0g run` serves the app to a page with hot reload: on the device over
`adb reverse`, or in any browser from the dev server. `flutter_p0g run --aera`
does the same against AERA recovery.

## Install

```sh
dart pub global activate --source git https://github.com/p0g-stack/p0g --git-path pkgs/flutter_p0g
# a released tag:
dart pub global activate --source git https://github.com/p0g-stack/p0g --git-path pkgs/flutter_p0g --git-ref p0g-v<x.y.z>
```

Put `~/.pub-cache/bin` on `PATH`. The commands themselves are documented in
[pkgs/flutter_p0g_tool](../flutter_p0g_tool/README.md).

## What this package is

A launcher. It finds the Flutter SDK, checks its version, builds the tool
once, and runs it:

1. **The SDK**: `FLUTTER_ROOT` if set, else the SDK whose Dart runs the
   launcher, else `flutter` on `PATH`.
2. **The version**: `environment.flutter` in this package's `pubspec.yaml` is
   the one release it wraps. Any other version is refused, so the tool's
   `flutter_tools` and the app's web SDK always match.
3. **The host**: the tool package, resolved against that SDK's
   `packages/flutter_tools` (stock pub cannot resolve `sdk: flutter` from
   outside the SDK, so the launcher writes its own host pubspec with that
   override). Built once per SDK revision, checkout, pub cache and tool
   sources; a host is reused until one of those changes.
4. **The cache**: hosts live under `$XDG_CACHE_HOME/p0g/tool` (default
   `~/.cache/p0g/tool`). Removed when no running launcher holds them.
5. `flutter_tools` runs with this process's stdio, and its exit code is
   returned. Ctrl-C reaches the tool directly.

Nothing here is written into an app or into the SDK's `bin/cache`.

## Development

This package is a workspace member: `flutter pub get` at the repository root
resolves it. `dart test` covers the launcher's pass-through of arguments,
stdio and exit code, the SDK version check, snapshot reuse and a cold-cache
concurrent start.
