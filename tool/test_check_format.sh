#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

printf 'void main(){print("hello");}\n' >"$fixture/example.dart"
cp "$fixture/example.dart" "$fixture/original.txt"
if "$repo_root/tool/check_format.sh" "$fixture/example.dart" >/dev/null 2>&1; then
  printf 'error: formatting gate accepted unformatted Dart\n' >&2
  exit 1
fi
cmp "$fixture/example.dart" "$fixture/original.txt"

dart format "$fixture/example.dart" >/dev/null
"$repo_root/tool/check_format.sh" "$fixture/example.dart" >/dev/null
printf 'Formatting gate regression checks passed.\n'
