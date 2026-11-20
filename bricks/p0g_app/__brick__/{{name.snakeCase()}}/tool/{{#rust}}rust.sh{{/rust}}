#!/usr/bin/env bash
# rust/: points the crate and core at frb, writes the Dart bindings, builds
# the library for this machine (`dart run`, `dart test`, `flutter test`, a
# `dart compile exe` CLI) and, with flutter_p0g's patched frb, the
# single-threaded wasm for the page and its Web Workers. bootstrap.sh runs
# it; run it again after changing rust/src/api/.
#
# Requires flutter_p0g's verified patched cache. Run
# `flutter_p0g precache --frb --no-webui` before bootstrap. A missing cache
# is a failure, never an implicit native-only or Dart fallback.
# Pub uses a workspace-relative link; only ignored Cargo config is absolute.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
patched="$flutter_root/bin/cache/flutter_p0g/frb"

dart run tool/frb.dart "$patched"
codegen="$patched/bin/flutter_rust_bridge_codegen"
flutter pub get >/dev/null

"$codegen" generate
(cd rust && cargo build --release)
(
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
)
dart format core/lib/src/rust >/dev/null
