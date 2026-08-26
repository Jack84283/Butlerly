#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/tool/toolchain.env"

multiline_output='Warning: Flutter should not be run as root.
Some unrelated wrapper output.
Dart SDK version: '"$DART_VERSION"' (stable) (Tue Aug 19 12:00:00 2026 +0000) on "linux_x64"
Another unrelated line.'

actual="$({ printf '%s\n' "$multiline_output"; } | "$repo_root/tool/verify_toolchain.sh" --extract-dart-version)"

if [[ "$actual" != "$DART_VERSION" ]]; then
  printf 'error: expected Dart version parser to extract %s, got <%s>\n' "$DART_VERSION" "$actual" >&2
  exit 1
fi

printf 'Dart version parser regression check passed.\n'
