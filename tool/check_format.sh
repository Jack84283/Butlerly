#!/usr/bin/env bash
set -euo pipefail

# Temporary PR diagnostic: show the exact formatter rewrite before failing.
dart format "$@"
if ! git diff --quiet -- "$@"; then
  git diff -- "$@"
  exit 1
fi
