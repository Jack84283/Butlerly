#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if dart format --output=none --set-exit-if-changed "$@"; then
  exit 0
fi

# Diagnose formatting drift using probes alongside the source files, keeping
# their package language version and formatter configuration unchanged.
if [[ "$PWD" == */apps/butlerly ]]; then
  probes=()
  cleanup() {
    for probe in "${probes[@]}"; do
      rm -f "$probe"
    done
  }
  trap cleanup EXIT
  for file in \
    lib/features/foundation/presentation/settings_page.dart; do
    probe="${file%.dart}_ci_format_probe.dart"
    cp "$file" "$probe"
    probes+=("$probe")
    dart format "$probe" >/dev/null
    diff -u "$file" "$probe" || true
  done
fi
exit 1
