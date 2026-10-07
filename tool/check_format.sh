#!/usr/bin/env bash
set -euo pipefail

# Temporary CI formatting probe for the transaction-detail redesign.
if [[ -f lib/features/foundation/presentation/transactions_page.dart ]]; then
  dart format lib/features/foundation/presentation/transactions_page.dart
  git diff -- lib/features/foundation/presentation/transactions_page.dart
  exit 1
fi

dart format --output=none --set-exit-if-changed "$@"
