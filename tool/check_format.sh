#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if dart format --output=none --set-exit-if-changed "$@"; then
  exit 0
fi

# TEMPORARY diagnostics for changed Flutter files.
if [[ "$PWD" == */apps/butlerly ]]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  if [[ -f lib/features/foundation/presentation/transactions_page.dart ]]; then
    cp lib/features/foundation/presentation/transactions_page.dart "$tmp_dir/transactions_page.dart"
    dart format "$tmp_dir/transactions_page.dart" >/dev/null
    diff -u lib/features/foundation/presentation/transactions_page.dart "$tmp_dir/transactions_page.dart" || true
  fi
  if [[ -f test/design_system/butlerly_modal_sheet_test.dart ]]; then
    cp test/design_system/butlerly_modal_sheet_test.dart "$tmp_dir/butlerly_modal_sheet_test.dart"
    dart format "$tmp_dir/butlerly_modal_sheet_test.dart" >/dev/null
    diff -u test/design_system/butlerly_modal_sheet_test.dart "$tmp_dir/butlerly_modal_sheet_test.dart" || true
  fi
fi
exit 1
