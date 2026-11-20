#!/usr/bin/env sh
# Check out the patched Squadron series (third_party/squadron at the repository
# root) into .upstream/squadron and point pub at it. Run once after cloning,
# and again whenever third_party/squadron/PIN or its patches change.
#
#   pkgs/squadron_process/tool/squadron.sh [--no-override]
#
# The tree is branch p0g/squadron of `tool/patches.sh squadron checkout`; edit
# the series there and export it with `tool/patches.sh squadron export`.
# Apps outside this repository use `dart run squadron_process:squadron_patch`.
set -eu

case "${1:-}" in
  '' | --no-override) ;;
  *) echo 'usage: tool/squadron.sh [--no-override]' >&2; exit 2 ;;
esac

pkg=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(CDPATH= cd -- "$pkg/../.." && pwd)
pin="$root/third_party/squadron/PIN"
package=$(sed -n 's/^package=//p' "$pin")
src="$root/.upstream/squadron${package:+/$package}"

"$root/tool/patches.sh" squadron checkout
commit=$(git -C "$root/.upstream/squadron" rev-parse --short=12 HEAD)
version=$(awk '/^version: / { print $2; exit }' "$src/pubspec.yaml")
echo "squadron $version (p0g/squadron at $commit) at $src"

old="$pkg/third_party/squadron/src"
if [ -d "$old" ]; then
  echo "note: $old is no longer used; remove it when convenient"
fi

[ "${1:-}" = --no-override ] && exit 0

marker='# Written by tool/squadron.sh. Points pub at the patched Squadron.'
overrides="$pkg/pubspec_overrides.yaml"
entry="dependency_overrides:
  squadron:
    path: ../../.upstream/squadron${package:+/$package}"
# Replace only a file this script wrote; anything else is the user's.
if [ -e "$overrides" ] && [ "$(sed -n 1p "$overrides")" != "$marker" ]; then
  echo "$overrides exists and was not written by tool/squadron.sh; leaving it." >&2
  echo "Add this entry to it (or remove it and rerun):" >&2
  echo "$entry" >&2
  exit 1
fi
printf '%s\n%s\n' "$marker" "$entry" > "$overrides"
echo "wrote $overrides"
