#!/usr/bin/env bash
# Prints the pinned Flutter release (.fvmrc, the repository's single Flutter
# version literal) and the Dart release inside it, from Flutter's stable
# release index, as GITHUB_OUTPUT lines:
#   flutter=3.50.0
#   dart=3.14.0
#   bash .github/scripts/flutter-dart-version.sh [FVMRC]
# Needs curl and jq.
set -euo pipefail

fvmrc=${1:-$(cd "$(dirname "$0")/../.." && pwd)/.fvmrc}
index=https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json

flutter=$(jq -er '.flutter | strings' "$fvmrc") || { echo "$fvmrc: no \"flutter\" version" >&2; exit 1; }
[[ $flutter =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$fvmrc: '$flutter' is not a stable Flutter release" >&2; exit 1; }
dart=$(curl -fsSL --retry 3 "$index" |
  jq -er --arg v "$flutter" '[.releases[] | select(.channel == "stable" and .version == $v)][0].dart_sdk_version | strings') ||
  { echo "Flutter $flutter: not in the stable release index $index" >&2; exit 1; }
dart=${dart%% *}
[[ $dart =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Flutter $flutter: unexpected Dart version '$dart'" >&2; exit 1; }
echo "flutter=$flutter"
echo "dart=$dart"
