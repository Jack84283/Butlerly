#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/apps/butlerly"
dart format   lib/features/foundation/presentation/transactions_page.dart   test/features/transactions/transaction_lifecycle_test.dart
