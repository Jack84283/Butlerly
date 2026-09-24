#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if [[ "$PWD" == */apps/butlerly ]]; then
  echo "=== FORMAT payment_settlements_page.dart ==="
  dart format --output=show lib/features/tools/presentation/payment_settlements_page.dart
  echo "=== FORMAT tools_page_test.dart ==="
  dart format --output=show test/features/tools/tools_page_test.dart
  echo "=== END FORMAT DIAGNOSTIC ==="
fi

dart format --output=none --set-exit-if-changed "$@"
