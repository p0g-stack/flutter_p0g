#!/usr/bin/env bash
# Regenerates this workspace from the p0g_app brick with the vars in
# tool/p0g_app.json and compares it with this checkout. Every file the brick
# generates must match (after the same `dart format` tool/bootstrap.sh runs),
# except entries in tool/regen.allow (may differ or be absent) and
# tool/regen.add (may only gain lines). Files the app adds are not checked.
#
#   BRICKS_REF=<full 40-hex bricks commit> bash tool/regen.sh
#   bash tool/regen.sh --brick-path <p0g_app brick directory>   # brick CI only
#
# BRICKS_REF lives in CI and the bump instructions, not here. Exit 0: matches;
# 1: differs; 64: usage. Needs mason (mason_cli 0.1.4), flutter and dart.
set -euo pipefail

usage() {
  echo "usage: BRICKS_REF=<full 40-hex bricks commit> bash tool/regen.sh" >&2
  echo "       bash tool/regen.sh --brick-path <p0g_app brick directory>" >&2
  exit 64
}

root="$(cd "$(dirname "$0")/.." && pwd)"
brick_path=
case $# in
  0) ;;
  2) [ "$1" = --brick-path ] || usage; brick_path="$2" ;;
  *) usage ;;
esac
config="$root/tool/p0g_app.json"
[ -f "$config" ] || { echo "missing tool/p0g_app.json (written by p0g_app)" >&2; exit 64; }

if [ -n "$brick_path" ]; then
  [ -f "$brick_path/brick.yaml" ] || {
    echo "--brick-path: no brick.yaml in $brick_path" >&2; exit 64
  }
  brick_path="$(cd "$brick_path" && pwd)"
  q="'"
  source="    path: '${brick_path//$q/$q$q}'"
  label="$brick_path"
else
  ref="${BRICKS_REF:-}"
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || {
    echo "BRICKS_REF must be a full 40-hex bricks commit, got '$ref'" >&2; usage
  }
  source="    git:
      url: https://github.com/p0g-stack/bricks
      path: bricks/p0g_app
      ref: $ref"
  label="p0g_app @ ${ref:0:12}"
fi

# Entries: `<path>  # <reason>`, one per line, beneath the generated header
# comments. Prints `<allow|add><TAB><path><TAB><file>:<line>` per entry.
lists=()
for list in tool/regen.allow tool/regen.add; do
  [ -f "$root/$list" ] && lists+=("$list")
done
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ "${#lists[@]}" -gt 0 ]; then
  (cd "$root" && awk '
    FNR == 1 { kind = (FILENAME == "tool/regen.allow") ? "allow" : "add" }
    /^[[:space:]]*(#|$)/ { next }
    {
      at = FILENAME ":" FNR
      i = index($0, "#")
      path = i ? substr($0, 1, i - 1) : $0
      reason = i ? substr($0, i + 1) : ""
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", path)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", reason)
      if (path ~ /[[:space:]]/) {
        print at ": one path, then # reason: " $0 > "/dev/stderr"; bad = 1; next
      }
      if (reason == "") {
        print at ": " path " needs a # reason" > "/dev/stderr"; bad = 1; next
      }
      if (path == "tool/regen.allow" || path == "tool/regen.add") {
        print at ": " path " is always checked additively; it cannot be listed" > "/dev/stderr"
        bad = 1; next
      }
      if (path in seen) {
        print at ": " path " is already listed at " seen[path] > "/dev/stderr"
        bad = 1; next
      }
      seen[path] = at
      print kind "\t" path "\t" at
    }
    END { exit bad }
  ' "${lists[@]}") > "$work/entries" || exit 1
else
  : > "$work/entries"
fi
listed() { # kind path
  awk -F '\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { found = 1 } END { exit !found }' \
    "$work/entries"
}

cat > "$work/mason.yaml" <<YAML
bricks:
  p0g_app:
$source
YAML
(cd "$work" && mason get >/dev/null &&
  mason make p0g_app -c "$config" -o "$work/out" --on-conflict overwrite >/dev/null)
out=("$work"/out/*/)
[ "${#out[@]}" = 1 ] && [ -d "${out[0]}" ] || {
  echo "expected one generated workspace in $work/out" >&2; exit 1
}
gen="${out[0]%/}"
fail=0

# Only what the brick (and its hook) writes, not what pub get adds.
(cd "$gen" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$work/files"
# Format needs the package graph; the stock Squadron is enough for that.
if ! (cd "$gen" && flutter pub get && dart format core cli app/lib app/test) \
  > "$work/format.log" 2>&1; then
  cat "$work/format.log" >&2
  echo "could not format the generated workspace" >&2
  exit 1
fi

while IFS=$'\t' read -r _ path at; do
  if ! grep -qxF -- "$path" "$work/files"; then
    echo "stale: $at lists $path, which $label does not generate"; fail=1
  fi
done < "$work/entries"

# Every generated line must still be there, in order.
additions_only() { # rel
  local removed
  removed="$(diff "$gen/$1" "$root/$1" | grep '^<' || true)"
  if [ -n "$removed" ]; then
    echo "changes brick lines (only additions allowed): $1"
    printf '%s\n' "$removed" | head -20 || true; fail=1
  fi
}

while IFS= read -r rel; do
  case "$rel" in
    tool/regen.allow | tool/regen.add) additive=1 ;;
    *)
      if listed allow "$rel"; then continue; fi
      if listed add "$rel"; then additive=1; else additive=0; fi
      ;;
  esac
  if [ ! -f "$root/$rel" ]; then
    echo "missing: $rel"; fail=1
  elif [ "$additive" = 1 ]; then
    additions_only "$rel"
  elif ! cmp -s "$gen/$rel" "$root/$rel"; then
    echo "differs: $rel"; diff -u "$gen/$rel" "$root/$rel" | head -40 || true; fail=1
  fi
done < "$work/files"

[ "$fail" = 0 ] && echo "matches $label (allowed: tool/regen.allow, additions: tool/regen.add)"
exit "$fail"
