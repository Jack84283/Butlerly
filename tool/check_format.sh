#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift and print the exact formatter diff for CI diagnostics.
dart format "$@"
if ! git diff --quiet -- .; then
  git --no-pager diff -- .
  exit 1
fi
