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
  dart format lib/features/foundation/presentation/review_page.dart
  git diff -- lib/features/foundation/presentation/review_page.dart
  exit 1
)

validate_integration_test() (
  cd apps/butlerly
  flutter test -d "${BUTLERLY_IOS_DEVICE_ID:-macos}" integration_test/v1_journeys_test.dart
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
  android_smoke)
    validate_android_smoke
    ;;
  *)
    echo "Usage: $0 [all|finance_domain|database|finance_application|flutter_application|integration_test|android_smoke]" >&2
    exit 2
    ;;
esac
