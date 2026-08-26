#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$repo_root/tool/toolchain.env"

extract_dart_version() {
  awk '!found && $1 == "Dart" && $2 == "SDK" && $3 == "version:" { print $4; found = 1 }'
}

if [[ "${1:-}" == "--extract-dart-version" ]]; then
  extract_dart_version
  exit 0
fi

actual_flutter="unavailable"
actual_dart="unavailable"

if command -v flutter >/dev/null 2>&1; then
  actual_flutter="$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')"
fi
if command -v dart >/dev/null 2>&1; then
  actual_dart="$(dart --version 2>&1 | extract_dart_version)"
fi

printf 'Expected Flutter version: %s\n' "$FLUTTER_VERSION"
printf 'Actual Flutter version:   %s\n' "$actual_flutter"
printf 'Expected Dart version:    %s\n' "$DART_VERSION"
printf 'Actual Dart version:      %s\n' "$actual_dart"

if [[ "$actual_flutter" != "$FLUTTER_VERSION" || "$actual_dart" != "$DART_VERSION" ]]; then
  printf 'error: Butlerly requires Flutter %s with Dart %s. Install the pinned toolchain before continuing.\n' \
    "$FLUTTER_VERSION" "$DART_VERSION" >&2
  exit 1
fi
