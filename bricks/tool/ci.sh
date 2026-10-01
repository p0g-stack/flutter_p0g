#!/usr/bin/env bash
# Generate each brick into a scratch folder and build and test what it made.
# Usage: tool/ci.sh [out-dir]. Needs flutter (3.47.5) and mason on PATH;
# the rust variant also needs cargo.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$(mktemp -d)}"
mkdir -p "$out"
cd "$root"
mason get

make_app() { # name rust process_place
  printf '{"name":"%s","description":"Generated in CI.","org":"dev.p0g.ci","rust":%s,"process_place":%s}' \
    "$1" "$2" "$3" > "$out/$1.json"
  mason make p0g_app -c "$out/$1.json" -o "$out" --on-conflict overwrite
}

echo "::group::p0g_app (defaults)"
make_app ci_app false false
app="$out/ci_app"
(
  cd "$app"
  bash tool/bootstrap.sh
  dart format --output=none --set-exit-if-changed core cli app/lib app/test
  dart analyze --fatal-infos
  (cd core && dart test)
  (cd cli && dart test)
  (cd app && flutter test)
  mkdir -p build
  dart compile exe cli/bin/ci_app.dart -o build/ci_app
  ./build/ci_app hello ci
  ./build/ci_app facts
  (cd app && flutter build web)
  if [ "${SKIP_LINUX:-}" != 1 ]; then (cd app && flutter build linux); fi
)
echo "::endgroup::"

echo "::group::p0g_app (rust)"
make_app ci_rust true false
(
  cd "$out/ci_rust"
  flutter pub get
  (cd rust && cargo test)
)
echo "::endgroup::"

# process_place resolves squadron_process from git; enable once it has a
# pubspec on main.
if [ "${WITH_PROCESS_PLACE:-}" = 1 ]; then
  echo "::group::p0g_app (process_place)"
  make_app ci_process false true
  (cd "$out/ci_process" && bash tool/bootstrap.sh && dart analyze)
  echo "::endgroup::"
fi
