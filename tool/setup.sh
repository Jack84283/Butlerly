#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

./tool/check_toolchain_consistency.sh
./tool/verify_toolchain.sh

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
