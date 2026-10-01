#!/usr/bin/env bash
# Check out squadron_process at the commit the pubspecs pin and build the
# patched Squadron it needs, under .p0g/ (see pubspec_overrides.yaml).
set -euo pipefail
cd "$(dirname "$0")/.."

commit=daf4a21b5cfcefb40afafb14bcaa7bc41d079545
dir=.p0g/squadron_process
if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" fetch -q --depth 1 https://github.com/p0g-stack/squadron_process "$commit"
  git -C "$dir" checkout -q --detach FETCH_HEAD
fi
sh "$dir/tool/squadron.sh" --no-override
