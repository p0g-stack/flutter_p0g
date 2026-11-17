#!/usr/bin/env bash
# Generate each brick into a scratch folder and build and test what it made.
# Usage: tool/ci.sh [out-dir]. Needs flutter (3.47.5) and mason on PATH;
# the Rust variants also need cargo, cargo-expand, wasm-pack and the verified
# patched FRB cache (`flutter_p0g precache --frb --no-webui`).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$(mktemp -d)}"
mkdir -p "$out"
cd "$root"
mason get

make_app() { # name rust sample [parent-dir]
  local dir="${4:-$out}"
  mkdir -p "$dir"
  printf '{"name":"%s","description":"Generated in CI.","org":"dev.p0g.ci","rust":%s,"sample":%s}' \
    "$1" "$2" "$3" > "$out/$1.json"
  mason make p0g_app -c "$out/$1.json" -o "$dir" --on-conflict overwrite
  # Lint with this checkout's p0g_lints, not the commit the brick pins.
  python3 - "$dir/$1/analysis_options.yaml" "$root/packages/p0g_lints" <<'PY'
import re, sys
f, path = sys.argv[1], sys.argv[2]
s = open(f).read()
s, n = re.subn(r"  p0g_lints:\n    git:\n(      .*\n)+", f"  p0g_lints:\n    path: {path}\n", s)
assert n == 1, "p0g_lints block not found"
open(f, "w").write(s)
PY
}

# sample=false: no hello service, panel or command, and no digest command.
no_sample() { # workspace
  ! grep -rqE 'HelloService|HelloPanel|HelloCommand|DigestCommand|hello_' \
    "$1/core/lib" "$1/core/test" "$1/cli/lib" "$1/cli/test" "$1/app/lib" "$1/app/test"
}

# With no service registered, serve is a usage error before it opens a
# socket or writes its session file.
serve_refuses() { # cli-exe
  local tmp code=0
  tmp="$(mktemp -d)"
  "$1" serve --session-file "$tmp/place.json" 2> "$tmp/serve.err" || code=$?
  cat "$tmp/serve.err"
  [ "$code" = 64 ]
  grep -qxF 'No services registered; add a service before using serve.' "$tmp/serve.err"
  [ ! -e "$tmp/place.json" ]
  rm -r "$tmp"
}

# Every file under a workspace with its hash, to prove a refused brick
# changed nothing.
snapshot() { # dir
  (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
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
make_app ci_app false true
app="$out/ci_app"
# Feature bricks run in the workspace root (their hooks find core/pubspec.yaml).
mason make service -o "$app" --name partitions --panel true
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
printf '{"name":"cbm","description":"Canoe Boot Manager sample.","org":"dev.p0g","rust":false,"sample":true}' > "$out/cbm.json"
mason make p0g_app -c "$out/cbm.json" -o "$out" --on-conflict overwrite
mason make service -o "$out/cbm" --name partitions --panel true
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
make_app ci_rust true true
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

# The sample=false workspaces live under a path with spaces.
spaced="$out/with spaces"

echo "::group::service preflight: a missing marker writes nothing"
make_app ci_marker false false
ws="$out/ci_marker"
panels="$ws/app/lib/panels/panels.dart"
serve_cmd="$ws/cli/lib/src/commands/serve_command.dart"
sed -i '/\/\/ p0g:panels/d' "$panels"
cp "$panels" "$out/panels.dart.before"
before="$(snapshot "$ws")"
# A panel needs the panels marker: refused before Mason writes anything.
if mason make service -o "$ws" --name probe --panel true --on-conflict overwrite; then
  echo "service with panel ran without the p0g:panels marker" >&2
  exit 1
fi
[ "$(snapshot "$ws")" = "$before" ]
# Without a panel it does not need that marker, and leaves panels.dart alone.
mason make service -o "$ws" --name probe --panel false --on-conflict overwrite
cmp "$panels" "$out/panels.dart.before"
[ ! -e "$ws/app/lib/panels/probe_panel.dart" ]
[ "$(grep -cF "'probe': withLogs(ProbeServiceWorker())" "$serve_cmd")" = 1 ]
# Missing serve marker: a new service is refused and nothing changes...
sed -i '/\/\/ p0g:services/d' "$serve_cmd"
before="$(snapshot "$ws")"
if mason make service -o "$ws" --name other --panel false --on-conflict overwrite; then
  echo "service ran without the p0g:services marker" >&2
  exit 1
fi
[ "$(snapshot "$ws")" = "$before" ]
[ ! -e "$ws/core/lib/src/service/other_service.dart" ]
# ...while re-making one already inserted needs no marker and adds nothing.
mason make service -o "$ws" --name probe --panel false --on-conflict overwrite
[ "$(grep -cF "'probe': withLogs(ProbeServiceWorker())" "$serve_cmd")" = 1 ]
[ "$(grep -c "addCommand(ProbeCommand());" "$ws/cli/lib/src/runner.dart")" = 1 ]
echo "::endgroup::"

echo "::group::p0g_app (sample false) + service with and without a panel"
make_app ci_bare false false "$spaced"
bare="$spaced/ci_bare"
no_sample "$bare"
(
  cd "$bare"
  bash tool/bootstrap.sh # no service: no worker to compile
  dart format --output=none --set-exit-if-changed core cli app/lib app/test
  dart analyze --fatal-infos
  (cd core && dart test)
  (cd cli && dart test)
  (cd app && flutter test)
  mkdir -p build
  dart compile exe cli/bin/ci_bare.dart -o build/ci_bare
  ./build/ci_bare facts
  serve_refuses ./build/ci_bare
)
mason make service -o "$bare" --name probe --panel true
mason make service -o "$bare" --name relay --panel false
grep -q 'ProbePanel.inPlace,' "$bare/app/lib/panels/panels.dart"
if grep -q 'Relay' "$bare/app/lib/panels/panels.dart"; then
  echo "relay was made with --panel false but has a panel" >&2
  exit 1
fi
[ ! -e "$bare/app/lib/panels/relay_panel.dart" ]
(
  cd "$bare"
  bash tool/bootstrap.sh # now with the services' workers
  dart format --output=none --set-exit-if-changed core cli app/lib app/test
  dart analyze --fatal-infos
  (cd core && dart test)
  (cd cli && dart test)
  (cd app && flutter test)
  dart compile exe cli/bin/ci_bare.dart -o build/ci_bare
  [ "$(./build/ci_bare probe from the cli)" = 'from the cli' ]
  [ "$(./build/ci_bare relay from the cli)" = 'from the cli' ]
  # Both services answer from the CLI's serve, as a process place.
  cat > cli/test/ci_process_test.dart <<'DART'
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:ci_bare_core/ci_bare_core.dart';
import 'package:squadron_process/io.dart';
import 'package:squadron_process/squadron_process.dart';
import 'package:test/test.dart';

void main() {
  test('both services answer from the process place', () async {
    final dir = await Directory.systemTemp.createTemp('p0g');
    addTearDown(() => dir.delete(recursive: true));
    final session = '${dir.path}/place.json';
    final place = ProcessPlace(
      launcher: const IoProcessLauncher(),
      store: FileEndpointStore(session),
      command: ProcessCommand(
        Platform.resolvedExecutable,
        arguments: [
          'run',
          'bin/ci_bare.dart',
          'serve',
          '--session-file',
          session,
          '--grace-ms',
          '200',
        ],
      ),
      readyTimeout: const Duration(minutes: 2),
    );
    final probe = place.bind(ProbeServiceWorker(), service: 'probe');
    addTearDown(probe.terminate);
    final relay = place.bind(RelayServiceWorker(), service: 'relay');
    addTearDown(relay.terminate);
    expect(await probe.echo('to probe'), 'to probe');
    expect(await relay.echo('to relay'), 'to relay');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
DART
  # The probe panel, the only one, answers through its local worker.
  cat > app/test/ci_panel_test.dart <<'DART'
import 'package:ci_bare/home.dart';
import 'package:ci_bare/places/places.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the probe panel echoes through its local worker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(places: Places(process: () => null), lines: LogLines()),
      ),
    );
    expect(find.text('Echo'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'from the panel');
    // A real isolate: let real time pass while the worker starts and answers.
    await tester.runAsync(() async => tester.tap(find.text('Echo')));
    // The input field and the answer both read 'from the panel'.
    for (var i = 0; i < 300; i++) {
      if (find.text('from the panel').evaluate().length == 2) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('from the panel'), findsNWidgets(2));
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
    });
  });
}
DART
  (cd cli && dart test test/ci_process_test.dart)
  (cd app && flutter test test/ci_panel_test.dart)
  rm cli/test/ci_process_test.dart app/test/ci_panel_test.dart
  (cd app && flutter build web)
)
echo "::endgroup::"

echo "::group::p0g_app (sample false, rust): the digest seed stays"
make_app ci_bare_rust true false "$spaced"
bare_rust="$spaced/ci_bare_rust"
no_sample "$bare_rust"
# The digest test calls the objective directly, not through a service.
grep -q "digest runs Rust in this place" "$bare_rust/core/test/digest_test.dart"
(
  cd "$bare_rust"
  bash tool/bootstrap.sh # no service: no worker to compile
  # The first bootstrap must be complete: repeated Pub/codegen must not add
  # or change files a consumer would commit (including platform registrants).
  git init -q
  before="$(git ls-files --others --exclude-standard -z | sort -z | xargs -0 sha256sum)"
  bash tool/bootstrap.sh
  [ "$(git ls-files --others --exclude-standard -z | sort -z | xargs -0 sha256sum)" = "$before" ]
  python3 - <<'PY'
import json, pathlib, urllib.parse
root = pathlib.Path.cwd()
config = root / '.dart_tool/package_config.json'
packages = {p['name']: p for p in json.loads(config.read_text())['packages']}
for name, relative in [('flutter_rust_bridge', '.dart_tool/p0g/frb/frb_dart'),
                       ('squadron', '.dart_tool/third_party/squadron-fd5becc4a480')]:
    uri = urllib.parse.urljoin(config.as_uri(), packages[name]['rootUri'])
    resolved = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path)).resolve()
    assert resolved == (root / relative).resolve(), (name, resolved)
for lock in ['pubspec.lock', 'rust/Cargo.lock']:
    text = (root / lock).read_text()
    assert str(root) not in text and str(pathlib.Path.home()) not in text, lock
assert 'path: ".dart_tool/p0g/frb/frb_dart"' in (root / 'pubspec.lock').read_text()
print('Portable patched sources, relative locks and second bootstrap: passed')
PY
  code=0
  dart run tool/frb.dart "$out/missing-frb" > "$out/missing-frb.log" 2>&1 || code=$?
  [ "$code" != 0 ]
  grep -F 'PathNotFoundException' "$out/missing-frb.log"
  dart format --output=none --set-exit-if-changed core cli app/lib app/test
  dart analyze --fatal-infos
  (cd rust && cargo test)
  # SHA-256 of abc through Rust, with rust_sha2 selected in this place.
  (cd core && dart test)
  (cd cli && dart test)
  (cd app && flutter test)
  mkdir -p build
  dart compile exe cli/bin/ci_bare_rust.dart -o build/ci_bare_rust
  cp rust/target/release/libci_bare_rust_native.so build/
  (cd / && "$bare_rust/build/ci_bare_rust" facts | grep -F '"native": true')
  code=0
  ./build/ci_bare_rust digest abc || code=$?
  [ "$code" = 64 ] # the digest command is part of the sample
  serve_refuses ./build/ci_bare_rust
  (cd app && flutter build web)
)
echo "::endgroup::"
