#!/usr/bin/env bash
# Patched Squadron, pub get, Squadron codegen, stock platform folders, web
# workers. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

# squadron_process needs Squadron with its channel-factory patch: resolve,
# fetch the patched copy into .dart_tool and override to it, resolve again.
flutter pub get
(cd cli && dart run squadron_process:squadron_patch ..)
flutter pub get
(cd core && dart run build_runner build --delete-conflicting-outputs)

# Stock platform folders; `flutter_p0g create .` adds webui/ and aera/.
(cd app && flutter create --no-pub --org {{org}} \
  --project-name {{name.snakeCase()}} --platforms "${PLATFORMS:-linux,web}" .)
rm -f app/pubspec.lock # the workspace has one lockfile, at the root

bash tool/build_workers.sh
dart format core cli app/lib app/test
