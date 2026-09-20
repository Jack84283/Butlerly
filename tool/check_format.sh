#!/usr/bin/env bash
set -euo pipefail

# TEMPORARY PR diagnostic: print the exact formatter diff before failing.
dart format "$@"
if ! git diff --quiet -- "$@"; then
  git diff -- "$@"
  exit 1
fi
