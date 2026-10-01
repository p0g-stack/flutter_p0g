#!/usr/bin/env bash
# Compiles the Squadron Web Worker entry points into app/web/workers/, where
# the generated activator looks for them ('~/workers/...', relative to the
# page's base href). Run after `dart run build_runner build` in core/ and
# before `flutter build web` / `flutter run -d chrome`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/app/web/workers"
mkdir -p "$out"
cd "$root/core"
for entry in lib/src/service/*.web.g.dart; do
  name="$(basename "$entry")"
  dart compile js -O2 --no-source-maps "$entry" -o "$out/$name.js"
  rm -f "$out/$name.js.deps"
done
