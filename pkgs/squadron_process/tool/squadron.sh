#!/usr/bin/env sh
# Materialize the patched Squadron into third_party/squadron/src and point pub
# at it. Run once after cloning, and again whenever PIN or patches/ change.
#
#   tool/squadron.sh [--no-override]
#
# An app that depends on squadron_process needs the same patched tree; it can
# run this script against its own checkout of squadron_process and add the
# printed dependency_overrides entry to its pubspec_overrides.yaml.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dir="$root/third_party/squadron"
src="$dir/src"
. "$dir/PIN"

if [ ! -d "$src/.git" ]; then
  git init -q "$src"
  git -C "$src" remote add origin "$repo"
fi
git -C "$src" fetch -q --depth 1 origin "$commit"
git -C "$src" checkout -q --force --detach "$commit"
git -C "$src" clean -q -fdx
for p in "$dir"/patches/*.patch; do
  git -C "$src" apply --whitespace=nowarn "$p"
done
echo "squadron $tag ($commit) + $(ls "$dir"/patches/*.patch | wc -l | tr -d ' ') patch(es) at $src"

if [ "${1:-}" != "--no-override" ]; then
  cat > "$root/pubspec_overrides.yaml" <<YAML
# Written by tool/squadron.sh. Points pub at the patched Squadron.
dependency_overrides:
  squadron:
    path: third_party/squadron/src
YAML
  echo "wrote pubspec_overrides.yaml"
fi
