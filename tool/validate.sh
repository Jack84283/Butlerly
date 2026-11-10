#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

format_check() {
  "$repo_root/tool/check_format.sh" .
}

./tool/check_toolchain_consistency.sh
./tool/verify_toolchain.sh
"$repo_root/tool/test_check_format.sh"

validate_finance_domain() (
  cd packages/butlerly_finance_domain
  format_check
  dart analyze --fatal-infos
  dart test
)

validate_finance_application() (
  cd packages/butlerly_finance_application
  format_check
  dart analyze --fatal-infos
  dart test
)

validate_database() (
  cd packages/butlerly_database
  format_check
  dart analyze --fatal-infos
  dart test
)

validate_flutter_application() (
  cd apps/butlerly
  format_check
  flutter analyze
  flutter test
  flutter build web
)

validate_integration_test() (
  cd apps/butlerly
  flutter test -d "${BUTLERLY_IOS_DEVICE_ID:-macos}" integration_test/v1_journeys_test.dart
)

validate_restore_journeys() (
  cd apps/butlerly
  local device="${BUTLERLY_IOS_DEVICE_ID:-macos}"
  flutter test -d "$device" integration_test/v1_journeys_test.dart --plain-name "production backup restore page completes an encrypted replacement"
  flutter test -d "$device" integration_test/v1_journeys_test.dart --plain-name "production Replace refuses a blocked WAL reader and safely retries"
)

validate_ios_simulator() (
  cd apps/butlerly
  flutter build ios --simulator --no-codesign
)

validate_macos_backup() (
  cd apps/butlerly
  flutter test test/core/data/raw_restore_service_test.dart test/core/data/atomic_evidence_publication_test.dart
  flutter build macos --debug
)

validate_android_smoke() (
  cd apps/butlerly/android
  ./gradlew :app:testDebugUnitTest
  cd ../../..
  cd apps/butlerly
  flutter build apk --debug
)

case "${1:-all}" in
  all)
    validate_finance_domain
    validate_database
    validate_finance_application
    validate_flutter_application
    ;;
  finance_domain)
    validate_finance_domain
    ;;
  database)
    validate_database
    ;;
  finance_application)
    validate_finance_application
    ;;
  flutter_application)
    validate_flutter_application
    ;;
  integration_test)
    validate_integration_test
    ;;
  restore_journeys)
    validate_restore_journeys
    ;;
  android_smoke)
    validate_android_smoke
    ;;
  ios_simulator)
    validate_ios_simulator
    ;;
  macos_backup)
    validate_macos_backup
    ;;
  *)
    echo "Usage: $0 [all|finance_domain|database|finance_application|flutter_application|integration_test|restore_journeys|android_smoke|ios_simulator|macos_backup]" >&2
    exit 2
    ;;
esac
