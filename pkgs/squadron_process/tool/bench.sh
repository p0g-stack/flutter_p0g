#!/usr/bin/env bash
# Runs the place benchmark on the Dart VM and in headless Chromium.
#   tool/bench.sh [<chrome>]   (default: $CHROME_EXECUTABLE)
# Needs the patched Squadron (tool/squadron.sh). Prints Markdown tables.
set -euo pipefail
cd "$(dirname "$0")/.."
chrome="${1:-${CHROME_EXECUTABLE:-}}"
out=.dart_tool/bench
mkdir -p "$out/web"

dart compile exe -o "$out/serve" benchmark/serve.dart >/dev/null
dart compile exe -o "$out/vm" benchmark/vm.dart >/dev/null
echo "## VM (AOT)"
"$out/vm" "$out/serve"

if [ -z "$chrome" ]; then
  echo "No Chromium given; skipping the browser run." >&2
  exit 0
fi
dart compile js -O4 -o "$out/web/bench.dart.js" benchmark/web/bench.dart >/dev/null
dart compile js -O4 -o "$out/web/bench_worker.dart.js" benchmark/web/bench_worker.dart >/dev/null
cp benchmark/web/index.html "$out/web/"
echo
echo "## Chromium (dart2js)"
dart run benchmark/run_web.dart "$out/web" "$out/serve" "$chrome"
