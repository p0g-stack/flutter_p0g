#!/usr/bin/env bash
# Squadron runs services in Web Workers on the web; each worker is its own
# compiled entry point, served next to the app under workers/.
set -euo pipefail
cd "$(dirname "$0")/.."

out=app/web/workers
mkdir -p "$out"
for entry in core/lib/src/services/*.web.g.dart; do
  [ -e "$entry" ] || continue
  dart compile js -O2 "$entry" -o "$out/$(basename "$entry").js"
done
