#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

cd "$repo_root/apps/butlerly"
dart format --output=show test/core/di/workspace_restore_rules_test.dart

cd "$repo_root/packages/butlerly_finance_application"
dart format --output=show test/duplicate_review_use_cases_test.dart
