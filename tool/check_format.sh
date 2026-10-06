#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if ! dart format --output=none --set-exit-if-changed "$@"; then
  for target in     "lib/features/foundation/presentation/transactions_page.dart"     "test/features/transactions/transaction_lifecycle_test.dart"; do
    if [[ -f "$target" ]]; then
      original="$(mktemp)"
      cp "$target" "$original"
      dart format "$target" >/dev/null
      echo "=== FORMAT_DIFF:$target ==="
      diff -u "$original" "$target" || true
      echo "=== END_FORMAT_DIFF:$target ==="
      cp "$original" "$target"
      rm -f "$original"
    fi
  done
  exit 1
fi
