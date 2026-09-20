#!/usr/bin/env bash
set -euo pipefail

# Report formatting drift without changing the caller's files.
dart format "$@"
git diff -- .
exit 1
