#!/usr/bin/env bash
# Generate each brick into a scratch folder and build and test what it made.
# Usage: tool/ci.sh [out-dir]. Needs flutter (3.47.5) and mason on PATH;
# the rust variant also needs cargo, cargo-expand and flutter_rust_bridge_codegen
# built from frb 848e438 (see the generated tool/rust.sh).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$(mktemp -d)}"
mkdir -p "$out"
cd "$root"
mason get

make_app() { # name rust
  printf '{"name":"%s","description":"Generated in CI.","org":"dev.p0g.ci","rust":%s}' \
    "$1" "$2" > "$out/$1.json"
  mason make p0g_app -c "$out/$1.json" -o "$out" --on-conflict overwrite
  # Lint with this checkout's p0g_lints, not the commit the brick pins.
  python3 - "$out/$1/analysis_options.yaml" "$root/packages/p0g_lints" <<'PY'
import re, sys
f, path = sys.argv[1], sys.argv[2]
s = open(f).read()
s, n = re.subn(r"  p0g_lints:\n    git:\n(      .*\n)+", f"  p0g_lints:\n    path: {path}\n", s)
assert n == 1, "p0g_lints block not found"
open(f, "w").write(s)
PY
}

# Both p0g_lints rules fire in a generated workspace, and only where they
# should (a helper outside a strategy may read Platform).
check_lints() { # workspace app
  local ws="$1" app="$2"
  cat > "$ws/core/lib/src/lint_probe.dart" <<'DART'
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'facts/facts.dart';
import 'strategy/strategy.dart';

final class Probe extends ReadStrategy<int, bool> {
  const Probe();
  @override
  String get name => 'probe';
  @override
  Future<bool> run(int input, PlaceInfo place) async => Platform.isAndroid;
}

bool helper() => Platform.isLinux || kIsWeb;
DART
  cat > "$ws/app/lib/lint_probe.dart" <<DART
import 'package:flutter/foundation.dart';
import 'package:${app}_core/${app}_core.dart';

final class AppProbe extends ReadStrategy<int, bool> {
  const AppProbe();
  @override
  String get name => 'app_probe';
  @override
  Future<bool> run(int input, PlaceInfo place) async => kIsWeb;
}
DART
  local report
  report="$(cd "$ws" && dart analyze 2>&1 || true)"
  rm "$ws/core/lib/src/lint_probe.dart" "$ws/app/lib/lint_probe.dart"
  echo "$report" | grep -E "core_imports_flutter|strategy_reads_platform"
  [ "$(echo "$report" | grep -c "core/lib/src/lint_probe.dart:3:8 .*core_imports_flutter")" = 1 ]
  [ "$(echo "$report" | grep -c "core/lib/src/lint_probe.dart:13:.*strategy_reads_platform")" = 1 ]
  [ "$(echo "$report" | grep -c "app/lib/lint_probe.dart:9:.*strategy_reads_platform")" = 1 ]
  [ "$(echo "$report" | grep -c "strategy_reads_platform")" = 2 ]
}

echo "::group::p0g_lints"
(cd packages/p0g_lints && dart pub get && dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos)
echo "::endgroup::"

echo "::group::p0g_app (defaults) + service + strategy"
make_app ci_app false
app="$out/ci_app"
# Feature bricks run in the workspace root (their hooks find core/pubspec.yaml).
mason make service -o "$app" --name partitions
mason make strategy -o "$app" --name fetch_partition --strategies '["dd", "fastboot fetch"]' --write false
mason make strategy -o "$app" --name flash --strategies '["dd"]' --write true
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
  ./build/ci_app partitions ci
  ./build/ci_app facts
  check_lints "$app" ci_app
  (cd app && flutter build web)
  if [ "${SKIP_LINUX:-}" != 1 ]; then (cd app && flutter build linux); fi
)
echo "::endgroup::"

echo "::group::sample: partition fetch (docs/samples)"
printf '{"name":"cbm","description":"Canoe Boot Manager sample.","org":"dev.p0g","rust":false}' > "$out/cbm.json"
mason make p0g_app -c "$out/cbm.json" -o "$out" --on-conflict overwrite
mason make service -o "$out/cbm" --name partitions
mason make strategy -o "$out/cbm" --name fetch_partition --strategies '["dd", "fastboot fetch"]' --write false
(
  cd "$out/cbm"
  git apply "$root/docs/samples/partition-fetch.patch"
  PLATFORMS=web bash tool/bootstrap.sh
  dart format --output=none --set-exit-if-changed core cli app/lib app/test
  dart analyze --fatal-infos
  (cd core && dart test)
  (cd cli && dart test)
  dart run cli/bin/cbm.dart partitions --how
)
echo "::endgroup::"

echo "::group::p0g_app (rust)"
make_app ci_rust true
(
  cd "$out/ci_rust"
  bash tool/bootstrap.sh
  dart format --output=none --set-exit-if-changed core cli app/lib app/test
  dart analyze --fatal-infos
  (cd rust && cargo test)
  (cd core && dart test)
  (cd cli && dart test)
  (cd app && flutter test)
  # As flutter_p0g packs it: the library beside the CLI. Run from outside the
  # workspace so only that copy can be found.
  mkdir -p build
  dart compile exe cli/bin/ci_rust.dart -o build/ci_rust
  cp rust/target/release/libci_rust_native.so build/
  (cd / && "$out/ci_rust/build/ci_rust" digest abc | grep -q rust_sha2)
  (cd app && flutter build web)
)
echo "::endgroup::"
