#!/usr/bin/env bash
# Generate each brick into a scratch folder and build and test what it made.
# Usage: tool/ci.sh [out-dir]. Needs git, python3, flutter (3.50.0) on PATH,
# a Chrome or Chromium (CHROME_EXECUTABLE, else google-chrome / chromium on
# PATH), the Linux desktop build tools, and for the Rust variants cargo,
# cargo-expand and wasm-pack.
#
# The candidate is the repository's HEAD commit: bricks/ and every pkgs/
# package at that commit, released together under the tag p0g-v<version>.
# Generated apps keep the production dependencies
# (https://github.com/p0g-stack/p0g at p0g-v* tags); this process alone
# points that URL at a local bare mirror holding HEAD under that one tag.
# Pub, the analyzer, Mason and the flutter_p0g launcher keep their caches in
# a scratch folder removed on exit, so nothing resolved from the candidate
# lands in a persistent cache under the production URL. The flutter_p0g CLI
# and Mason are activated there (the CLI from the mirror) and are what PATH
# finds. The working tree is not read or written; uncommitted changes are
# not tested.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)" # the p0g repository
p0g_url=https://github.com/p0g-stack/p0g
out="${1:-$(mktemp -d)}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

chrome="${CHROME_EXECUTABLE:-$(command -v google-chrome || command -v google-chrome-stable ||
  command -v chromium || command -v chromium-browser || true)}"
if [ -z "$chrome" ]; then
  echo "No Chrome or Chromium: set CHROME_EXECUTABLE." >&2
  exit 1
fi
flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
real_pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"

# No spaces: pub's binstubs do not quote the cache path.
candidate="$(mktemp -d)"
trap 'rm -rf "$candidate"' EXIT

commit="$(git -C "$repo" rev-parse --verify 'HEAD^{commit}')"
if [ -n "$(git -C "$repo" status --porcelain -- bricks pkgs)" ]; then
  echo "::warning::Testing HEAD $commit; uncommitted changes in bricks/ or pkgs/ are not tested."
fi
# One release version: every package the tag releases has it at HEAD.
version="$(
  git -C "$repo" ls-tree -r --name-only "$commit" -- pkgs |
    grep -E '^pkgs/([^/]+|webui/[^/]+)/pubspec\.yaml$' |
    while read -r pubspec; do
      git -C "$repo" show "$commit:$pubspec" | sed -n 's/^version: *\([^ ]*\) *$/\1/p'
    done | sort -u
)"
if [ -z "$version" ] || [ "$(printf '%s\n' "$version" | wc -l)" != 1 ]; then
  echo "pkgs/ packages at HEAD do not share one version:" $version >&2
  exit 1
fi
tag="p0g-v$version"

# The mirror: HEAD under the release tag and nothing else. --update-shallow
# accepts a shallow CI checkout.
mirror="$candidate/p0g.git"
git init -q --bare "$mirror"
git -C "$mirror" fetch -q --no-tags --update-shallow "$repo" "+$commit:refs/tags/$tag"
[ "$(git -C "$mirror" rev-parse "refs/tags/$tag^{commit}")" = "$commit" ]

# bricks/ at HEAD; Mason writes its lock and compiled hooks there.
git -C "$repo" archive "$commit" bricks | tar -x -C "$candidate"
root="$candidate/bricks"

# This process and its children only: no global git config, no global caches.
n="${GIT_CONFIG_COUNT:-0}"
export "GIT_CONFIG_KEY_$n=url.$mirror.insteadOf" "GIT_CONFIG_VALUE_$n=$p0g_url"
export GIT_CONFIG_COUNT=$((n + 1))
export PUB_CACHE="$candidate/pub-cache"
export ANALYZER_STATE_LOCATION_OVERRIDE="$candidate/analyzer"
export MASON_CACHE="$candidate/mason-cache"
export XDG_CACHE_HOME="$candidate/cache" # the flutter_p0g launcher's tool host
export PATH="$PUB_CACHE/bin:$PATH"

echo "::group::candidate $tag at $commit: flutter_p0g, mason, precache"
dart pub global activate mason_cli 0.1.4
dart pub global activate --source git "$mirror" --git-path pkgs/flutter_p0g --git-ref "$tag"
[ "$(command -v flutter_p0g)" = "$PUB_CACHE/bin/flutter_p0g" ]
[ "$(command -v mason)" = "$PUB_CACHE/bin/mason" ]
# The verified patched FRB (Rust variants) and the Android Dart kit (the
# module's root process); both live in the Flutter SDK's cache.
flutter_p0g precache --frb --dart-android
echo "::endgroup::"

cd "$root"
mason get

make_app() { # name rust sample [parent-dir]
  local dir="${4:-$out}"
  mkdir -p "$dir"
  printf '{"name":"%s","description":"Generated in CI.","org":"dev.p0g.ci","rust":%s,"sample":%s}' \
    "$1" "$2" "$3" > "$out/$1.json"
  mason make p0g_app -c "$out/$1.json" -o "$dir" --on-conflict overwrite
}

# A bootstrapped workspace resolves this repository's packages as an outside
# consumer does: the production URL at the release tag (tag_pattern in
# pubspecs; the analyzer plugin names the tag as ref), locked at the
# candidate commit and version. No manifest a consumer commits names a path
# of this host (Flutter SDK, pub caches, the scratch mirror, the workspace).
check_manifests() { # workspace
  python3 - "$1" "$p0g_url" "$commit" "$version" \
    "$candidate" "$flutter_root" "$real_pub_cache" "$HOME" <<'PY'
import pathlib, re, sys
ws, url, commit, version, *host = sys.argv[1:]
root = pathlib.Path(ws).resolve()
host = [h for h in host + [str(root)] if len(h) > 1]
repo = re.compile(r'github\.com[/:]p0g-stack/p0g(\.git)?/?$')
yamls = [p for pattern in ['analysis_options.yaml', 'pubspec*.yaml', '*/analysis_options.yaml',
                           '*/pubspec*.yaml'] for p in sorted(root.glob(pattern))]
locks = [p for p in [root / 'pubspec.lock', root / 'rust' / 'Cargo.lock'] if p.exists()]
for manifest in yamls + locks:
    text = manifest.read_text()
    for h in host:
        assert h not in text, f'{manifest} names the host path {h}'

def blocks(lines, opener):
    """The `key: value` lines indented below each `opener` line, as a dict."""
    indent = lambda s: len(s) - len(s.lstrip())
    for i, line in enumerate(lines):
        m = opener.match(line)
        if not m:
            continue
        fields = {}
        for child in lines[i + 1:]:
            if child.strip() and indent(child) <= len(m.group(1)):
                break
            kv = re.match(r'\s+([\w-]+):\s*"?(.*?)"?\s*$', child)
            if kv:
                fields[kv.group(1)] = kv.group(2)
        yield fields

sources = 0
for manifest in yamls:
    for git in blocks(manifest.read_text().splitlines(), re.compile(r'^(\s*)git:\s*$')):
        if not repo.search(git.get('url', '')):
            continue
        sources += 1
        where = f"{manifest}: {git.get('path')}"
        assert git['url'] == url and git.get('path', '').startswith('pkgs/'), (where, git)
        if manifest.name == 'analysis_options.yaml':
            assert git.get('ref') == f'p0g-v{version}' and 'tag_pattern' not in git, (where, git)
        else:
            assert git.get('tag_pattern') == 'p0g-v{{version}}' and 'ref' not in git, (where, git)
assert sources, f'{root}: no dependency on {url}'

locked = 0
lock = (root / 'pubspec.lock').read_text()
for entry in blocks(lock.splitlines(), re.compile(r'^(    )description:\s*$')):
    if not repo.search(entry.get('url', '')):
        continue
    locked += 1
    assert entry['url'] == url and entry.get('resolved-ref') == commit, entry
    # Direct dependencies by tag; a package's path dependency on a sibling
    # (squadron_process on patched_source) is pinned to the same commit.
    assert entry.get('tag-pattern') == 'p0g-v{{version}}' or entry.get('ref') == commit, entry
versions = re.findall(r'url: "' + re.escape(url) + r'"\n    source: git\n    version: "([^"]+)"', lock)
assert locked and versions == [version] * locked, (locked, versions)
print(f'{root.name}: {locked} package(s) from {url} at {version} ({commit[:12]}); no host paths')
PY
}

# Serves a web build on loopback and loads it in headless Chrome: the engine
# creates its view and the page logs no uncaught error or exception.
web_smoke() { # build-dir
  local log="$candidate/smoke" server port code=0
  rm -rf "$log"
  mkdir -p "$log"
  python3 - "$1" "$log/port" > "$log/server.log" 2>&1 <<'PY' &
import functools, http.server, os, sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
with open(sys.argv[2] + '.tmp', 'w') as f:
    f.write(str(server.server_port))
os.replace(sys.argv[2] + '.tmp', sys.argv[2])
server.serve_forever()
PY
  server=$!
  for _ in $(seq 100); do [ -s "$log/port" ] && break; sleep 0.1; done
  port="$(cat "$log/port")"
  timeout 120 "$chrome" --headless=new --no-sandbox --disable-gpu --no-first-run \
    --user-data-dir="$log/profile" --enable-logging=stderr --v=0 \
    --virtual-time-budget=30000 --dump-dom "http://127.0.0.1:$port/" \
    > "$log/dom.html" 2> "$log/chrome.log" || code=$?
  kill "$server"
  wait "$server" 2> /dev/null || true
  grep ':CONSOLE' "$log/chrome.log" || true
  [ "$code" = 0 ]
  grep -q '<flutter-view' "$log/dom.html"
  ! grep ':CONSOLE' "$log/chrome.log" | grep -E 'Uncaught|Exception|Error'
}

# The module flutter_p0g packs: the stock page under webroot/ with
# flutter-webui's bootstrap and the services' workers, the root channel, and
# the app's CLI for the device.
check_module() { # app-dir cli-name
  python3 - "$1" "$2" <<'PY'
import pathlib, sys, zipfile
app, cli = pathlib.Path(sys.argv[1]), sys.argv[2]
[module] = (app / 'build' / 'webui').glob('*.zip')
names = set(zipfile.ZipFile(module).namelist())
need = ['module.prop', 'customize.sh', 'META-INF/com/google/android/update-binary',
        'webroot/index.html', 'webroot/flutter_bootstrap.js', 'webroot/flutter_webui.js',
        'webroot/main.dart.js', 'flutter_webui/root',
        'flutter_webui/arm64-v8a/flutter_webui_root.aot', 'flutter_webui/arm64-v8a/dartaotruntime',
        f'bin/{cli}', f'bin/arm64-v8a/{cli}.aot', 'bin/arm64-v8a/dartaotruntime']
missing = [n for n in need if n not in names]
assert not missing, (module.name, missing)
assert any(n.startswith('webroot/workers/') and n.endswith('.js') for n in names), module.name
print(f'{module.name}: {len(names)} files')
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

# p0g_lints is a workspace member now; the workspace job formats and analyzes it.

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
  check_manifests .
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
  if [ "${SKIP_LINUX:-}" != 1 ]; then (cd app && flutter build linux); fi
  # Stock web through the CLI: the page and the services' Web Workers, loaded
  # in a browser tab.
  (cd app && flutter_p0g build web)
  web_smoke "$app/app/build/web"
  # The WebUI module: the CLI's platform folders, then the zip with the root
  # channel and this app's CLI compiled for the device.
  (cd app && flutter_p0g create . && flutter_p0g build webui)
  check_module "$app/app" ci_app
  check_manifests .
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
  check_manifests .
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
  check_manifests .
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
  # Stock web through the CLI: the frb wasm runs in the page.
  (cd app && flutter_p0g build web)
  web_smoke "$out/ci_rust/app/build/web"
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
  check_manifests .
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
  check_manifests .
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
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
  check_manifests .
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
