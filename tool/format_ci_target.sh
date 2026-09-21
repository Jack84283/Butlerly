#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/apps/butlerly"
dart format   test/features/foundation/classification_interaction_test.dart   test/features/transactions/transaction_lifecycle_test.dart
