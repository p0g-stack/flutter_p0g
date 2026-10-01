#!/usr/bin/env bash
# rust/: points the crate and core at frb, writes the Dart bindings, builds
# the library for this machine (`dart run`, `dart test`, `flutter test`, a
# `dart compile exe` CLI) and, with flutter_p0g's patched frb, the
# single-threaded wasm for the page and its Web Workers. bootstrap.sh runs
# it; run it again after changing rust/src/api/.
#
# frb comes from, in order:
# 1. flutter_p0g's patched frb (`flutter_p0g precache --frb`): native and web.
# 2. frb at 848e438 with `flutter_rust_bridge_codegen` on PATH (or
#    FRB_CODEGEN) built from that commit:
#      cargo install --git https://github.com/fzyzcjy/flutter_rust_bridge \
#        --rev 848e438c561491adcc16cbf8b33bb61e541bd475 flutter_rust_bridge_codegen
#    Native only; the web build then has no Rust and uses Dart strategies.
#
# The links are local, so they go in gitignored files, as squadron_patch does
# for Squadron: rust/.cargo/config.toml and pubspec_overrides.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."

frb_rev=848e438c561491adcc16cbf8b33bb61e541bd475
flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
patched="$flutter_root/bin/cache/flutter_p0g/frb"

web=0
mkdir -p rust/.cargo
echo '*' > rust/.cargo/.gitignore
if [ -x "$patched/bin/flutter_rust_bridge_codegen" ]; then
  codegen="$patched/bin/flutter_rust_bridge_codegen"
  web=1
  cat > rust/.cargo/config.toml <<TOML
# Written by tool/rust.sh: flutter_p0g's patched frb.
[patch.crates-io]
flutter_rust_bridge = { path = "$patched/src/frb_rust" }
TOML
  if ! grep -q '^  flutter_rust_bridge:' pubspec_overrides.yaml 2>/dev/null; then
    [ -f pubspec_overrides.yaml ] || echo 'dependency_overrides:' > pubspec_overrides.yaml
    cat >> pubspec_overrides.yaml <<YAML
  # flutter_p0g's patched frb (tool/rust.sh).
  flutter_rust_bridge:
    path: $patched/src/frb_dart
YAML
  fi
  flutter pub get >/dev/null
else
  codegen="${FRB_CODEGEN:-flutter_rust_bridge_codegen}"
  if ! command -v "$codegen" >/dev/null; then
    echo "No frb codegen: run \`flutter_p0g precache --frb\`, or install it from $frb_rev (see tool/rust.sh)." >&2
    exit 1
  fi
  cat > rust/.cargo/config.toml <<TOML
# Written by tool/rust.sh: frb at the commit core/pubspec.yaml pins.
[patch.crates-io]
flutter_rust_bridge = { git = "https://github.com/fzyzcjy/flutter_rust_bridge", rev = "$frb_rev" }
TOML
fi

"$codegen" generate
(cd rust && cargo build --release)
if [ "$web" = 1 ]; then
  # wasm-pack runs wasm-opt from PATH, or downloads binaryen. Before 117 it
  # breaks the module (its externref table fails to grow at init), and the
  # download fails offline. Unoptimized output is correct, so without a
  # good wasm-opt a pass-through one goes first on PATH, as in flutter_p0g.
  wasm_opt=$( (wasm-opt --version 2>/dev/null || true) | sed -n 's/.*version \([0-9]*\).*/\1/p')
  if [ "${wasm_opt:-0}" -lt 117 ]; then
    echo "rust.sh: no wasm-opt 117+ (found ${wasm_opt:-none}); the wasm ships unoptimized."
    shim=rust/target/wasm-opt-passthrough
    mkdir -p "$shim"
    cat > "$shim/wasm-opt" <<'SH'
#!/bin/sh
# tool/rust.sh: pass-through wasm-opt (wasm-opt <in> -o <out> <passes...>).
in=; out=
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    --version) echo "wasm-opt version passthrough"; exit 0 ;;
    -*) shift ;;
    *) [ -z "$in" ] && in=$1; shift ;;
  esac
done
[ -n "$in" ] && [ -n "$out" ] || exit 0
[ "$in" = "$out" ] || cp "$in" "$out"
SH
    chmod +x "$shim/wasm-opt"
    PATH="$PWD/$shim:$PATH"
  fi
  "$codegen" build-web --no-threads --release --dart-root core -o "$PWD/app/web"
else
  echo "rust.sh: no patched frb, so no wasm; on the web the Dart strategies run."
fi
dart format core/lib/src/rust >/dev/null
