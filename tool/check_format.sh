#!/usr/bin/env bash
set -euo pipefail

# Temporary PR formatting diagnostic. Remove after capturing the exact dartfmt diff.
if [[ "$PWD" == */apps/butlerly ]]; then
  dart format test/features/transactions/transaction_lifecycle_test.dart >/dev/null
  git --no-pager diff -- test/features/transactions/transaction_lifecycle_test.dart
  exit 1
fi

# Report formatting drift without changing the caller's files.
dart format --output=none --set-exit-if-changed "$@"
