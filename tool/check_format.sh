#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if dart format --output=none --set-exit-if-changed "$@"; then
  exit 0
fi

# TEMPORARY diagnostic for the transaction details file.
if [[ "$PWD" == */apps/butlerly ]]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  cp lib/features/foundation/presentation/transactions_page.dart "$tmp_dir/transactions_page.dart"
  dart format "$tmp_dir/transactions_page.dart" >/dev/null
  diff -u lib/features/foundation/presentation/transactions_page.dart "$tmp_dir/transactions_page.dart" || true
fi
exit 1
