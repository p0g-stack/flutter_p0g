#!/usr/bin/env bash
# Patched Squadron, pub get, Squadron codegen, stock platform folders, web
# workers. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

# Stock platform folders; `flutter_p0g create .` adds webui/ and aera/.
# Create them before Pub so the first bootstrap also writes plugin registrants.
(cd app && flutter create --no-pub --org {{org}} \
  --project-name {{name.snakeCase()}} --platforms "${PLATFORMS:-linux,web}" .)
rm -f app/pubspec.lock # the workspace has one lockfile, at the root

# squadron_process needs Squadron with its channel-factory patch: resolve,
# fetch the patched copy into .dart_tool and override to it, resolve again.
flutter pub get
(cd cli && dart run squadron_process:squadron_patch ..)
dart run tool/third_party.dart
flutter pub get
{{#rust}}bash tool/rust.sh
{{/rust}}
(cd core && dart run build_runner build --delete-conflicting-outputs)

bash tool/build_workers.sh
dart format core cli app/lib app/test
# p0g:after-bootstrap
