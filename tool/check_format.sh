#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if format_output="$(dart format --output=none --set-exit-if-changed "$@" 2>&1)"; then
  printf '%s\n' "$format_output"
  exit 0
fi
printf '%s\n' "$format_output"

# Provide actionable diffs for the files actually reported by the formatter.
# Format temporary sibling probes so package language and formatter settings
# are identical; never modify the original files during validation.
probes=()
cleanup() {
  for probe in "${probes[@]}"; do
    rm -f "$probe"
  done
}
trap cleanup EXIT

while IFS= read -r line; do
  [[ "$line" == Changed\ *.dart ]] || continue
  file="${line#Changed }"
  [[ -f "$file" ]] || continue
  probe="${file%.dart}_ci_format_probe.dart"
  cp "$file" "$probe"
  probes+=("$probe")
  dart format "$probe" >/dev/null
  diff -u "$file" "$probe" || true
  # Keep a large unrelated formatting failure from overwhelming CI logs.
  if (( ${#probes[@]} >= 10 )); then
    break
  fi
done <<< "$format_output"
exit 1
