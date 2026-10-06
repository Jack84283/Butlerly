#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if ! dart format --output=none --set-exit-if-changed "$@"; then
  target="lib/features/foundation/presentation/transaction_record_list.dart"
  if [[ -f "$target" ]]; then
    original="$(mktemp)"
    cp "$target" "$original"
    dart format "$target" >/dev/null
    echo "=== TRANSACTION_RECORD_LIST_FORMAT_DIFF ==="
    diff -u "$original" "$target" || true
    echo "=== END_TRANSACTION_RECORD_LIST_FORMAT_DIFF ==="
    cp "$original" "$target"
    rm -f "$original"
  fi
  exit 1
fi
