#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if dart format --output=none --set-exit-if-changed "$@"; then
  exit 0
fi

# TEMPORARY diagnostic for the transaction details file.
if [[ -f lib/features/foundation/presentation/transactions_page.dart ]]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  dart format --output=show lib/features/foundation/presentation/transactions_page.dart \
    >"$tmp_dir/transactions_page.dart"
  diff -u lib/features/foundation/presentation/transactions_page.dart "$tmp_dir/transactions_page.dart" || true
fi
exit 1
