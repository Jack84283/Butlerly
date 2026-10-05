#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if ! dart format --output=none --set-exit-if-changed "$@"; then
  home_file="lib/features/foundation/presentation/home_page.dart"
  if [[ -f "$home_file" ]]; then
    original="$(mktemp)"
    cp "$home_file" "$original"
    dart format "$home_file" >/dev/null
    echo "=== HOME_PAGE_DART_FORMAT_DIFF ==="
    diff -u "$original" "$home_file" || true
    echo "=== END_HOME_PAGE_DART_FORMAT_DIFF ==="
    cp "$original" "$home_file"
    rm -f "$original"
  fi
  exit 1
fi
