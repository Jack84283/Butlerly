#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY formatting diagnostic: show the formatter's exact diff.
dart format "$@"
if ! git diff --exit-code -- apps/butlerly/lib/features/foundation/presentation/transactions_page.dart; then
  exit 1
fi
