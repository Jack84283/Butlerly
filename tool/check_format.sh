#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if dart format --output=none --set-exit-if-changed "$@"; then
  exit 0
fi

# Diagnose app formatting drift in CI without changing the checkout.
if [[ "$PWD" == */apps/butlerly ]]; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  for file in \
    lib/features/foundation/presentation/transactions_page.dart \
    lib/design_system/theme/butlerly_surface_gradients.dart \
    test/design_system/semantic_palette_gradient_test.dart; do
    cp "$file" "$tmp_dir/$(basename "$file")"
    dart format "$tmp_dir/$(basename "$file")" >/dev/null
    diff -u "$file" "$tmp_dir/$(basename "$file")" || true
  done
fi
exit 1
