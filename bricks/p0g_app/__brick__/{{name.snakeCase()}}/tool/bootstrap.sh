#!/usr/bin/env bash
# Resolve the workspace, generate Squadron workers, add stock platform folders
# and compile the web workers. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
(cd core && dart run build_runner build --delete-conflicting-outputs)

# Stock platform folders; `flutter_p0g create .` adds webui/ and aera/.
(cd app && flutter create --no-pub --org {{org}} \
  --project-name {{name.snakeCase()}}_app --platforms "${PLATFORMS:-linux,web}" .)
rm -f app/pubspec.lock # the workspace has one lockfile, at the root

bash tool/build_web_workers.sh
dart format core cli app/lib app/test
