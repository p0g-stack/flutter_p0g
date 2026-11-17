#!/usr/bin/env bash
# Publishes files as assets of a GitHub release without ever replacing one.
# Each FILE is matched to the release asset of the same basename:
#   absent                      -> uploaded, then downloaded back and compared
#   present, identical bytes    -> skipped
#   present, different bytes    -> refused; the release is left as it is and
#                                  the changed bytes need a new tag
# Every present asset is downloaded and compared before anything is uploaded,
# so a refusal uploads nothing.
#
#   immutable-release-upload.sh [-R OWNER/REPO] [--commit SHA] TAG FILE... [-- CREATE_ARGS...]
#
#   -R OWNER/REPO  repository; defaults to $GH_REPO, then $GITHUB_REPOSITORY
#   --commit SHA   TAG must resolve to this full commit SHA: checked before a
#                  missing release is created (an existing tag elsewhere
#                  refuses) and again before comparing or uploading
#   -- ARGS        create a missing release with `gh release create TAG
#                  [--target SHA] ARGS` (title, notes, --prerelease, ...);
#                  without them a missing release is an error. A release a
#                  concurrent job created first is used as it is.
#
# Needs gh (signed in) and jq. Canonical copy, kept byte-identical in
# flutter-aera, flutter_p0g and webui-termux-api under .github/scripts/;
# immutable-release-upload-test.sh beside it is its fixture.
set -euo pipefail
shopt -s inherit_errexit

die() { echo "immutable-release-upload: $*" >&2; exit 1; }
usage() { echo "usage: ${0##*/} [-R OWNER/REPO] [--commit SHA] TAG FILE... [-- CREATE_ARGS...]" >&2; exit 64; }

repo=${GH_REPO:-${GITHUB_REPOSITORY:-}}
commit=
while [ $# -gt 0 ]; do
  case $1 in
    -R) [ $# -ge 2 ] || usage; repo=$2; shift 2 ;;
    --commit) [ $# -ge 2 ] || usage; commit=$2; shift 2 ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -ge 2 ] || usage
tag=$1
shift
files=()
create=()
while [ $# -gt 0 ]; do
  if [ "$1" = -- ]; then
    shift
    create=("$@")
    break
  fi
  files+=("$1")
  shift
done
[ ${#files[@]} -gt 0 ] || usage

[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "no repository: pass -R OWNER/REPO or set GH_REPO/GITHUB_REPOSITORY"
[[ $tag =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "unsupported tag name '$tag'"
[ -z "$commit" ] || [[ $commit =~ ^[0-9a-f]{40}$ ]] || die "--commit needs a full 40-hex commit SHA, got '$commit'"

declare -A given=()
for f in "${files[@]}"; do
  [ -f "$f" ] || die "$f: not a file"
  n=${f##*/}
  # GitHub rewrites other names on upload, which would hide the asset from
  # the comparison below.
  [[ $n =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "$n: asset names are limited to [A-Za-z0-9._+-], starting alphanumeric"
  [ -z "${given[$n]:-}" ] || die "$n: given twice"
  given[$n]=1
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# gh api PATH; status 2 for HTTP 404, 1 for any other failure.
api_get() {
  if gh api "$1" 2>"$tmp/err"; then return 0; fi
  if grep -q 'HTTP 404' "$tmp/err"; then return 2; fi
  cat "$tmp/err" >&2
  return 1
}

# The commit TAG resolves to (through annotated tags); empty if no such tag.
tag_commit() {
  local json rc=0 type sha
  json=$(api_get "repos/$repo/git/ref/tags/$tag") || rc=$?
  [ $rc -ne 2 ] || return 0
  [ $rc -eq 0 ] || die "cannot read tag $tag of $repo"
  type=$(jq -r .object.type <<<"$json")
  sha=$(jq -r .object.sha <<<"$json")
  while [ "$type" = tag ]; do
    json=$(api_get "repos/$repo/git/tags/$sha") || die "cannot read annotated tag object $sha"
    type=$(jq -r .object.type <<<"$json")
    sha=$(jq -r .object.sha <<<"$json")
  done
  [ "$type" = commit ] || die "tag $tag points to a $type, not a commit"
  echo "$sha"
}

# check_commit [allow-absent]
check_commit() {
  [ -n "$commit" ] || return 0
  local actual
  actual=$(tag_commit)
  if [ -z "$actual" ] && [ "${1:-}" = allow-absent ]; then return 0; fi
  [ "$actual" = "$commit" ] || die "tag $tag is at ${actual:-no commit}, not $commit; publish under a new tag"
}

# The release's id; empty if TAG has no (published) release.
release_id() {
  local json rc=0
  json=$(api_get "repos/$repo/releases/tags/$tag") || rc=$?
  [ $rc -ne 2 ] || return 0
  [ $rc -eq 0 ] || die "cannot read release $tag of $repo"
  jq -r .id <<<"$json"
}

# fetch NAME DIR: downloads the released asset NAME into DIR.
fetch() {
  mkdir -p "$2"
  gh release download "$tag" -R "$repo" -p "$1" -D "$2"
  [ -f "$2/$1" ] || die "$1: download of the released asset produced no file"
}

sha256() { sha256sum <"$1" | cut -c1-64; }

check_commit allow-absent
id=$(release_id)
if [ -z "$id" ]; then
  [ ${#create[@]} -gt 0 ] || die "release $tag does not exist in $repo"
  target=()
  [ -z "$commit" ] || target=(--target "$commit")
  gh release create "$tag" -R "$repo" "${target[@]}" "${create[@]}" ||
    echo "immutable-release-upload: creating $tag failed; using it if a concurrent job created it" >&2
  id=$(release_id)
  [ -n "$id" ] || die "release $tag was not created"
fi
check_commit

declare -A state=()
gh api --paginate "repos/$repo/releases/$id/assets?per_page=100" -q '.[] | "\(.name)\t\(.state)"' >"$tmp/assets"
while IFS=$'\t' read -r n s; do
  if [ -n "$n" ]; then state[$n]=$s; fi
done <"$tmp/assets"

absent=()
refused=0
for f in "${files[@]}"; do
  n=${f##*/}
  if [ -z "${state[$n]+set}" ]; then
    absent+=("$f")
    continue
  fi
  if [ "${state[$n]}" != uploaded ]; then
    echo "REFUSED $n: the released asset is in state '${state[$n]}'; it is not replaced" >&2
    refused=1
    continue
  fi
  fetch "$n" "$tmp/released/$n"
  if cmp -s "$f" "$tmp/released/$n/$n"; then
    echo "skipped $n: identical to the released asset ($(sha256 "$f"))"
  else
    echo "REFUSED $n: released sha256 $(sha256 "$tmp/released/$n/$n"), local $(sha256 "$f")" >&2
    refused=1
  fi
done
[ $refused -eq 0 ] || die "release $tag keeps its assets and nothing was uploaded; publish changed bytes under a new tag"

if [ ${#absent[@]} -gt 0 ]; then
  gh release upload "$tag" -R "$repo" "${absent[@]}"
  for f in "${absent[@]}"; do
    n=${f##*/}
    fetch "$n" "$tmp/uploaded/$n"
    cmp -s "$f" "$tmp/uploaded/$n/$n" || die "$n: the uploaded asset does not match $f"
    echo "uploaded $n ($(sha256 "$f"))"
  done
fi
