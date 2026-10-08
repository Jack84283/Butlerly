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
  for file in \
    lib/features/foundation/presentation/transactions_page.dart \
    lib/features/foundation/presentation/search_page.dart \
    lib/features/foundation/presentation/transaction_record_list.dart \
    lib/features/insights/presentation/insights_page.dart; do
    name="$(basename "$file")"
    cp "$file" "$tmp_dir/$name"
    dart format "$tmp_dir/$name" >/dev/null
    diff -u "$file" "$tmp_dir/$name" || true
  done
fi
exit 1
