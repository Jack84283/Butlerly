#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/apps/butlerly"
dart format   lib/design_system/components/butlerly_transaction_controls.dart   test/features/transactions/transaction_lifecycle_test.dart
