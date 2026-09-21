#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/butlerly"
dart format --output=show test/core/di/workspace_restore_rules_test.dart
