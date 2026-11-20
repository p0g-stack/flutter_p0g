#!/usr/bin/env bash
# Work on p0g/<upstream>, rebase it, update PIN, then export. push takes
# the slug from NNNN-<slug>.patch; web_sdk is local-only and uses VERSION.
set -euo pipefail
export LC_ALL=C
shopt -s nullglob
fail() { printf 'patches: %s\n' "$*" >&2; exit 1; }
usage() { fail 'usage: tool/patches.sh <upstream> checkout|export|push [slug]'; }
(( $# >= 2 )) || usage
u=$1 cmd=$2 slug=${3-}
[[ $u =~ ^[a-z][a-z0-9_]*$ ]] || usage
case $cmd in
  checkout|export) (( $# == 2 )) || usage ;;
  push) (( $# == 3 )) && [[ $slug =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || usage ;;
  *) usage ;;
esac
root=$(cd "$(dirname "$0")/.." && pwd)
branch=p0g/$u
src=$root/.upstream/$u
series=$root/third_party/$u
tag=
if [[ $u == web_sdk ]]; then
  [[ $cmd != push ]] || fail 'the web SDK hooks are not upstream proposals'
  series=$root/web_sdk
  repo=https://github.com/flutter/flutter.git
  read -r tag < "$series/VERSION"
  commit=refs/tags/$tag
else
  [[ -f $series/PIN ]] || fail "missing $series/PIN"
  repo=$(sed -n 's/^repo=//p' "$series/PIN")
  commit=$(sed -n 's/^commit=//p' "$series/PIN")
  [[ -n $repo && $commit =~ ^[0-9a-f]{40}$ ]] || fail "invalid $series/PIN"
fi
patches=$series/patches
format=(-k -N --zero-commit --no-signature --no-stat --full-index)
g() { git -C "$src" "$@"; }
if [[ ! -d $src/.git ]]; then
  [[ $cmd == checkout && ! -e $src ]] || fail "expected an upstream checkout at $src"
  mkdir -p "$root/.upstream"
  # Preserve release history for rebase, without downloading old blobs.
  if [[ $u == web_sdk ]]; then
    git clone -q --filter=blob:none --no-checkout --depth=1 --branch "$tag" "$repo" "$src"
    g sparse-checkout set engine/src/flutter/lib/web_ui
  else
    git clone -q --filter=blob:none --no-checkout "$repo" "$src"
  fi
fi
[[ $(g config --get remote.origin.url) == "$repo" ]] || fail "different origin in $src"
# A --no-checkout clone has HEAD but no index or files yet.
if [[ -e $src/.git/index ]]; then
  [[ -z $(g status --porcelain) ]] || fail "uncommitted changes in $src"
fi
# CI runners need not have a global Git identity to replay the mail series.
if ! g var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
  export GIT_COMMITTER_NAME='p0g patch checkout' GIT_COMMITTER_EMAIL='patches@localhost'
fi
if [[ $cmd == checkout ]]; then
  if g show-ref --verify --quiet "refs/heads/$branch"; then
    [[ $(g rev-parse "$branch") == "$(g rev-parse --verify -q refs/p0g/exported || :)" ]] ||
      fail "unexported commits on $branch: export or preserve the branch first"
  fi
  if ! g cat-file -e "$commit^{commit}" 2>/dev/null; then
    if [[ $u == web_sdk ]]; then
      g fetch -q --depth=1 --filter=blob:none origin "$commit:$commit"
    else
      g fetch -q origin "$commit"
    fi
  fi
  g checkout -q -B "$branch" "$commit^{commit}"
  files=("$patches"/*.patch)
  if (( ${#files[@]} )); then g am -k --3way "${files[@]}"; fi
  g update-ref refs/p0g/exported HEAD
  exit
fi
[[ $(g branch --show-current) == "$branch" ]] || fail "switch to $branch first"
g merge-base --is-ancestor "$commit" HEAD || fail 'PIN is not an ancestor of the series'
range=$commit..HEAD
[[ -z $(g rev-list --merges "$range") ]] || fail 'expected a linear patch series'
if [[ $cmd == export ]]; then
  tmp=$(mktemp -d "$series/.export.XXXXXX")
  trap 'rm -rf -- "$tmp"' EXIT
  g format-patch "${format[@]}" -o "$tmp" "$range"
  # Only replace patch files; do not remove notes or change anything if
  # format-patch fails partway through writing the new series.
  mkdir -p "$patches"
  for file in "$patches"/*.patch; do [[ -f $tmp/${file##*/} ]] || rm -- "$file"; done
  for file in "$tmp"/*.patch; do mv -- "$file" "$patches/"; done
  g update-ref refs/p0g/exported HEAD
else
  matches=("$patches"/[0-9][0-9][0-9][0-9]-"$slug".patch)
  (( ${#matches[@]} == 1 )) || fail "no unique exported patch for $slug"
  [[ $(g rev-parse HEAD) == "$(g rev-parse --verify refs/p0g/exported)" ]] || fail 'export first'
  name=${matches[0]##*/}
  index=$((10#${name%%-*}))
  pick=$(g rev-list --reverse "$range" | sed -n "${index}p")
  [[ -n $pick ]] && g format-patch "${format[@]}" -1 --stdout "$pick" | cmp -s - "${matches[0]}" ||
    fail 'patch does not match its commit; export first'
  fork=https://github.com/p0g-stack/$u.git
  ref=refs/heads/$slug
  expected=$(git ls-remote --refs "$fork" "$ref" | cut -f1)
  g fetch origin HEAD
  # Keep the editable series intact even when the independent pick conflicts.
  tmp=$(mktemp -d "$root/.upstream/.push.XXXXXX")
  g worktree add --detach "$tmp" FETCH_HEAD
  trap 'g worktree remove --force "$tmp"' EXIT
  git -C "$tmp" cherry-pick "$pick"
  git -C "$tmp" push --force-with-lease="$ref:$expected" "$fork" "HEAD:$ref"
fi
