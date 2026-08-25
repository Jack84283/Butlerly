#!/usr/bin/env bash
set -euo pipefail

(
  cd packages/butlerly_finance_domain
  dart pub get
)

(
  cd packages/butlerly_finance_application
  dart pub get
)

(
  cd packages/butlerly_database
  dart pub get
)

(
  cd apps/butlerly
  flutter pub get
)
