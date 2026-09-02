#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

format_check() {
  local before after
  before="$(find . -type f -name '*.dart' -print0 | sort -z | xargs -0 sha256sum)"
  dart format --output=none . >/dev/null
  after="$(find . -type f -name '*.dart' -print0 | sort -z | xargs -0 sha256sum)"
  if [[ "$before" != "$after" ]]; then
    echo 'Dart formatting changed tracked source files.' >&2
    return 1
  fi
}

./tool/check_toolchain_consistency.sh
./tool/verify_toolchain.sh

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
  flutter test integration_test/v1_journeys_test.dart
)

validate_android_smoke() (
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
