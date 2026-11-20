#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
mode=${1:-all}
case "$mode" in all|frb|defines) ;; *) echo "usage: bash $0 [all|frb|defines]" >&2; exit 64;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p0g-web-runtime.XXXXXX")
echo "Proof outputs and logs: $work"
exec > >(tee "$work/run.log") 2>&1
flutter --version
node --version
cargo --version

copy_fixture() {
  cp -R "$here/$1" "$work/$1"
  local source
  while IFS= read -r -d '' source; do mv "$source" "${source%.in}"; done < <(find "$work/$1" -name '*.dart.in' -print0)
}

if [[ "$mode" != defines ]]; then
  pin=$(awk -F "'" '/^const kFrbCommit = / {print $2}' "$repo/lib/src/frb/frb.dart")
  test "${#pin}" = 40
  source=${FRB_SOURCE:-$work/frb-source}
  if [[ -z "${FRB_SOURCE:-}" ]]; then
    git init -q "$source"
    git -C "$source" remote add origin https://github.com/fzyzcjy/flutter_rust_bridge
    git -C "$source" fetch -q --depth 1 origin "$pin"
    git -C "$source" checkout -q FETCH_HEAD
    for patch in "$repo"/patches/frb/*.patch; do git -C "$source" apply "$patch"; done
  else
    test "$(git -C "$source" rev-parse HEAD)" = "$pin"
    for patch in "$repo"/patches/frb/*.patch; do git -C "$source" apply --reverse --check "$patch"; done
  fi
  codegen=${FRB_CODEGEN:-$source/target/release/flutter_rust_bridge_codegen}
  if [[ -z "${FRB_CODEGEN:-}" ]]; then
    (cd "$source" && cargo build --locked --release -p flutter_rust_bridge_codegen)
  fi
  copy_fixture frb
  cd "$work/frb"
  printf 'dependency_overrides:\n  flutter_rust_bridge:\n    path: "%s/frb_dart"\n' "$source" > pubspec_overrides.yaml
  mkdir -p rust/.cargo web
  printf '[patch.crates-io]\nflutter_rust_bridge = { path = "%s/frb_rust" }\nflutter_rust_bridge_macros = { path = "%s/frb_macros" }\n' "$source" "$source" > rust/.cargo/config.toml
  dart pub get
  "$codegen" generate --config-file flutter_rust_bridge.yaml
  "$codegen" build-web --no-threads --skip-tool-install --release
  dart compile js -O2 --no-source-maps lib/worker.dart -o web/worker.js
  node "$here/browser.mjs" frb "$work/frb/web" | tee "$work/frb-browser.json"
fi
if [[ "$mode" != frb ]]; then
  copy_fixture defines
  cd "$work/defines"
  flutter pub get
  # Invoke the actual local p0g command. Its getBuildInfo resolves both flag
  # and file definitions, then the normal build passes that list to workers.
  for compiler in js wasm; do
    for input in flags file; do
      args=(build web --release --no-web-resources-cdn --base-href /proof/ -o "$work/$compiler-$input/proof")
      [[ "$compiler" != wasm ]] || args+=(--wasm)
      if [[ "$input" == flags ]]; then
        args+=("--dart-define=P0G_WORKER_VALUE=a=b with spaces 日本語" --dart-define=P0G_WORKER_FLAG=true)
      else
        args+=(--dart-define-from-file=defines.json)
      fi
      dart --packages="$repo/.dart_tool/package_config.json" "$repo/bin/flutter_p0g.dart" "${args[@]}"
      node "$here/browser.mjs" defines "$work/$compiler-$input" "$compiler" | tee "$work/defines-$compiler-$input.json"
    done
  done
fi
