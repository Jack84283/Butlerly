#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
case "$PWD" in
  */packages/butlerly_finance_application)
    echo "=== FORMAT finance_application/payment_settlement_use_cases_test.dart ==="
    dart format --output=show test/payment_settlement_use_cases_test.dart
    ;;
  */packages/butlerly_database)
    echo "=== FORMAT database/backup_merge_migration_test.dart ==="
    dart format --output=show test/backup_merge_migration_test.dart
    echo "=== FORMAT database/payment_settlement_repository_test.dart ==="
    dart format --output=show test/payment_settlement_repository_test.dart
    ;;
  */apps/butlerly)
    echo "=== FORMAT app/local_backup_engine.dart ==="
    dart format --output=show lib/core/data/local_backup_engine.dart
    echo "=== FORMAT app/local_backup_manager_test.dart ==="
    dart format --output=show test/core/data/local_backup_manager_test.dart
    ;;
esac
echo "=== END FORMAT DIAGNOSTIC ==="

dart format --output=none --set-exit-if-changed "$@"
