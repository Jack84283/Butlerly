#!/usr/bin/env bash
set -euo pipefail

# Temporary formatter diagnostic: emit the exact formatter diff for changed files.
dart format "$@"
git diff -- .
exit 1
