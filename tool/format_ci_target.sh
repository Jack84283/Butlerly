#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/apps/butlerly"
dart format test/app/primary_bottom_navigation_clearance_test.dart
