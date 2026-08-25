#!/usr/bin/env bash
set -euo pipefail

(
  cd packages/butlerly_finance_domain
  dart format --output=none --set-exit-if-changed .
  dart analyze --fatal-infos
  dart test
)

(
  cd packages/butlerly_finance_application
  dart format --output=none --set-exit-if-changed .
  dart analyze --fatal-infos
  dart test
)

(
  cd packages/butlerly_database
  dart format --output=none --set-exit-if-changed .
  dart analyze --fatal-infos
  dart test
)

(
  cd apps/butlerly
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  flutter test
  flutter build web
)
