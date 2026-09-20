#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
if ! dart format --output=none --set-exit-if-changed "$@"; then
  dart format "$@"
  git diff -- .
  exit 1
fi
