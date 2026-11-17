#!/usr/bin/env bash
# Fixture for immutable-release-upload.sh: runs it against a fake `gh` that
# keeps one repository's tags, releases and assets in a temporary directory.
#   bash .github/scripts/immutable-release-upload-test.sh
# Kept byte-identical beside every copy of the script.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/immutable-release-upload.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export STORE=$tmp/store
mkdir -p "$STORE/tags" "$STORE/tagobjs" "$STORE/releases" "$tmp/bin" "$tmp/work"
: >"$STORE/log"
unset GH_REPO GITHUB_REPOSITORY

A=1111111111111111111111111111111111111111
B=2222222222222222222222222222222222222222

cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: only the calls immutable-release-upload.sh makes.
set -euo pipefail
echo "$*" >>"$STORE/log"
nf() { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
case $1 in
  api)
    shift
    q= path=
    while [ $# -gt 0 ]; do
      case $1 in
        --paginate) shift ;;
        -q | --jq) q=$2; shift 2 ;;
        *) path=$1; shift ;;
      esac
    done
    path=${path%%\?*}
    case $path in
      repos/o/r/git/ref/tags/*)
        t=${path#repos/o/r/git/ref/tags/}
        [ -f "$STORE/tags/$t" ] || nf
        read -r type sha <"$STORE/tags/$t"
        out=$(jq -n --arg type "$type" --arg sha "$sha" '{object: {type: $type, sha: $sha}}') ;;
      repos/o/r/git/tags/*)
        s=${path#repos/o/r/git/tags/}
        [ -f "$STORE/tagobjs/$s" ] || nf
        out=$(jq -n --arg sha "$(cat "$STORE/tagobjs/$s")" '{object: {type: "commit", sha: $sha}}') ;;
      repos/o/r/releases/tags/*)
        t=${path#repos/o/r/releases/tags/}
        [ -f "$STORE/releases/$t/id" ] || nf
        out=$(jq -n --argjson id "$(cat "$STORE/releases/$t/id")" --arg tag "$t" '{id: $id, tag_name: $tag}') ;;
      repos/o/r/releases/*/assets)
        id=${path#repos/o/r/releases/}
        id=${id%/assets}
        rel=
        for d in "$STORE"/releases/*/; do
          if [ "$(cat "$d/id")" = "$id" ]; then rel=$d; fi
        done
        [ -n "$rel" ] || nf
        out=$(cd "$rel/assets" && for n in *; do if [ -e "$n" ]; then printf '%s\n' "$n"; fi; done |
          jq -R '{name: ., state: "uploaded"}' | jq -s .) ;;
      *) echo "fake gh: unexpected api path $path" >&2; exit 3 ;;
    esac
    if [ -n "$q" ]; then jq -r "$q" <<<"$out"; else printf '%s\n' "$out"; fi ;;
  release)
    sub=$2 tag=$3
    shift 3
    rel=$STORE/releases/$tag
    case $sub in
      create)
        target=
        while [ $# -gt 0 ]; do
          case $1 in
            --target) target=$2; shift 2 ;;
            -R | --title | --notes) shift 2 ;;
            *) shift ;;
          esac
        done
        [ ! -d "$rel" ] || { echo "release $tag already exists" >&2; exit 1; }
        [ -f "$STORE/tags/$tag" ] || echo "commit ${target:?fake gh: create needs --target}" >"$STORE/tags/$tag"
        mkdir -p "$rel/assets"
        echo $((100 + $(ls "$STORE/releases" | wc -l))) >"$rel/id" ;;
      upload)
        files=()
        while [ $# -gt 0 ]; do
          case $1 in
            -R) shift 2 ;;
            --clobber) echo "fake gh: --clobber used" >&2; exit 3 ;;
            *) files+=("$1"); shift ;;
          esac
        done
        [ -d "$rel" ] || { echo "release not found" >&2; exit 1; }
        for f in "${files[@]}"; do
          [ ! -e "$rel/assets/${f##*/}" ] || { echo "asset under the same name already exists: ${f##*/}" >&2; exit 1; }
        done
        for f in "${files[@]}"; do cp "$f" "$rel/assets/"; done ;;
      download)
        p= dir=.
        while [ $# -gt 0 ]; do
          case $1 in
            -p) p=$2; shift 2 ;;
            -D) dir=$2; shift 2 ;;
            -R) shift 2 ;;
            *) echo "fake gh: unexpected download argument $1" >&2; exit 3 ;;
          esac
        done
        [ -f "$rel/assets/$p" ] || { echo "no assets match the file pattern" >&2; exit 1; }
        cp "$rel/assets/$p" "$dir/" ;;
      *) echo "fake gh: unexpected release $sub" >&2; exit 3 ;;
    esac ;;
  *) echo "fake gh: unexpected $1" >&2; exit 3 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

failures=0
ok() { echo "ok - $1"; }
bad() { echo "not ok - $1" >&2; sed 's/^/#   /' "$tmp/out" >&2; failures=$((failures + 1)); }
# run WANT DESC ARGS...: runs the script, checks its status, keeps its output.
run() {
  local want=$1 desc=$2 got=0
  shift 2
  : >"$STORE/log"
  "$script" "$@" >"$tmp/out" 2>&1 || got=$?
  if { [ "$want" = 0 ] && [ $got -eq 0 ]; } || { [ "$want" != 0 ] && [ $got -ne 0 ]; }; then
    return 0
  fi
  bad "$desc: exit $got, wanted $([ "$want" = 0 ] && echo 0 || echo nonzero)"
  return 1
}
uploads() { grep -c '^release upload' "$STORE/log" || true; }
creates() { grep -c '^release create' "$STORE/log" || true; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

w=$tmp/work
printf 'kit one' >"$w/kit.tar.xz"
printf 'sum one' >"$w/kit.tar.xz.sha256"
printf 'extra' >"$w/extra.bin"
rel=$STORE/releases/t1/assets

# Absent: the release is created at the commit and both assets are uploaded.
if run 0 "absent assets" -R o/r --commit $A t1 "$w/kit.tar.xz" "$w/kit.tar.xz.sha256" -- --title T --notes N; then
  check "absent assets are uploaded" 'cmp -s "$w/kit.tar.xz" "$rel/kit.tar.xz" && cmp -s "$w/kit.tar.xz.sha256" "$rel/kit.tar.xz.sha256"'
  check "missing release is created at the commit" '[ "$(cat "$STORE/tags/t1")" = "commit $A" ] && [ "$(creates)" = 1 ]'
fi

# Identical: nothing is uploaded or created.
if run 0 "identical assets" -R o/r --commit $A t1 "$w/kit.tar.xz" "$w/kit.tar.xz.sha256" -- --title T --notes N; then
  check "identical assets are skipped" '[ "$(uploads)" = 0 ] && [ "$(creates)" = 0 ] && grep -q "^skipped kit.tar.xz:" "$tmp/out"'
fi

# Identical plus a new one: only the new one is uploaded.
if run 0 "identical plus absent" -R o/r t1 "$w/kit.tar.xz" "$w/extra.bin"; then
  check "only the absent asset is uploaded" 'cmp -s "$w/extra.bin" "$rel/extra.bin" && grep -q "^release upload t1 -R o/r $w/extra.bin\$" "$STORE/log" && [ "$(uploads)" = 1 ]'
fi

# Different: refused, the released bytes stay, the absent file is not uploaded.
cp "$rel/kit.tar.xz" "$tmp/kept"
printf 'kit two' >"$w/kit.tar.xz"
printf 'new' >"$w/new.bin"
if run 1 "different asset" -R o/r t1 "$w/new.bin" "$w/kit.tar.xz"; then
  check "different asset is refused without replacement" 'cmp -s "$tmp/kept" "$rel/kit.tar.xz" && [ ! -e "$rel/new.bin" ] && [ "$(uploads)" = 0 ] && grep -q "^REFUSED kit.tar.xz:" "$tmp/out"'
fi

# --commit: an existing tag elsewhere refuses before a release is created.
echo "commit $B" >"$STORE/tags/t2"
if run 1 "tag at another commit" -R o/r --commit $A t2 "$w/extra.bin" -- --title T; then
  check "tag at another commit refuses before creating" '[ "$(creates)" = 0 ] && [ ! -d "$STORE/releases/t2" ]'
fi
if run 1 "release at another commit" -R o/r --commit $B t1 "$w/new.bin"; then
  check "release tagged at another commit refuses" '[ "$(uploads)" = 0 ] && [ ! -e "$rel/new.bin" ]'
fi

# --commit through an annotated tag.
tagobj=3333333333333333333333333333333333333333
echo "tag $tagobj" >"$STORE/tags/t3"
echo $A >"$STORE/tagobjs/$tagobj"
if run 0 "annotated tag" -R o/r --commit $A t3 "$w/extra.bin" -- --title T; then
  check "annotated tag resolves to its commit" 'cmp -s "$w/extra.bin" "$STORE/releases/t3/assets/extra.bin"'
fi

# Missing release without create arguments.
if run 1 "missing release" -R o/r t4 "$w/extra.bin"; then
  check "missing release without create arguments fails" '[ "$(creates)" = 0 ] && [ "$(uploads)" = 0 ]'
fi

# Names GitHub would rewrite, and the same name twice.
printf 'x' >"$w/a b.bin"
mkdir -p "$w/other"
cp "$w/extra.bin" "$w/other/extra.bin"
if run 1 "rewritten name" -R o/r t1 "$w/a b.bin"; then ok "name GitHub would rewrite is refused"; fi
if run 1 "duplicate name" -R o/r t1 "$w/extra.bin" "$w/other/extra.bin"; then ok "same asset name twice is refused"; fi

# Short --commit and no repository.
if run 1 "short commit" -R o/r --commit 1111111 t1 "$w/extra.bin"; then ok "abbreviated --commit is refused"; fi
if run 1 "no repository" t1 "$w/extra.bin"; then ok "missing repository is refused"; fi

if [ $failures -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
