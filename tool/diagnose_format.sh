#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/butlerly"
dart format --output=show test/design_system/butlerly_missing_master_data_test.dart
