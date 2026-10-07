#!/usr/bin/env bash
set -euo pipefail

# Temporary CI formatting probe for the transaction-detail lifecycle tests.
if [[ -f test/features/transactions/transaction_lifecycle_test.dart ]]; then
  dart format test/features/transactions/transaction_lifecycle_test.dart
  git diff -- test/features/transactions/transaction_lifecycle_test.dart
  exit 1
fi

dart format --output=none --set-exit-if-changed "$@"
