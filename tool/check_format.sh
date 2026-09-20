#!/usr/bin/env bash
set -euo pipefail

# Temporary PR formatting diagnostic; remove after capturing the exact diff.
if [[ "$PWD" == */apps/butlerly ]]; then
  dart format "$@"
  git --no-pager diff -- \
    lib/core/import/local_csv_importer.dart \
    lib/features/foundation/presentation/contextual_pages.dart \
    test/core/import/local_csv_importer_test.dart
  exit 1
fi

# Report formatting drift without changing the caller's files.
dart format --output=none --set-exit-if-changed "$@"
