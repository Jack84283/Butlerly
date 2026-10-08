#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if dart format --output=none --set-exit-if-changed "$@"; then
  exit 0
fi

# TEMPORARY diagnostic for the transaction details file.
if [[ "$PWD" == */apps/butlerly ]]; then
  source_file="lib/features/foundation/presentation/transactions_page.dart"
  tmp_file="lib/features/foundation/presentation/.format_tmp_transactions_page.dart"
  trap 'rm -f "$tmp_file"' EXIT
  cp "$source_file" "$tmp_file"
  dart format "$tmp_file" >/dev/null
  diff -u "$source_file" "$tmp_file" || true
fi
exit 1
