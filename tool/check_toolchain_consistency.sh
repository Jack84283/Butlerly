#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ci.yml"
action="$repo_root/.github/actions/setup-toolchain/action.yml"
pin="$repo_root/tool/toolchain.env"

fail() {
  printf 'error: toolchain consistency check failed: %s\n' "$1" >&2
  exit 1
}

[[ -f "$pin" ]] || fail 'tool/toolchain.env is missing'
[[ -f "$action" ]] || fail 'the shared CI toolchain action is missing'
# shellcheck disable=SC1090
source "$pin"
[[ -n "${FLUTTER_VERSION:-}" && -n "${DART_VERSION:-}" ]] ||
  fail 'tool/toolchain.env must define both SDK versions'

grep -q 'uses: ./.github/actions/setup-toolchain' "$workflow" ||
  fail 'CI must use the shared repository toolchain action'
grep -q './tool/setup.sh' "$workflow" || fail 'CI must invoke tool/setup.sh'
grep -q './tool/validate.sh' "$workflow" || fail 'CI must invoke tool/validate.sh'
grep -q 'tool/toolchain.env' "$action" || fail 'the shared action must consume tool/toolchain.env'
grep -q './tool/verify_toolchain.sh' "$action" || fail 'the shared action must verify installed SDK versions'

"$repo_root/tool/test_verify_toolchain.sh"

if grep -Eq 'channel:[[:space:]]*stable|sdk:[[:space:]]*stable' "$workflow"; then
  fail 'CI must not select a floating stable SDK'
fi

if grep -Eq 'dart (format|analyze|test)|flutter (analyze|test|build web)' "$workflow"; then
  fail 'canonical validation commands must remain in tool/validate.sh, not CI'
fi

while IFS= read -r file; do
  [[ "$file" == "$pin" ]] && continue
  if grep -Fq "$FLUTTER_VERSION" "$file" || grep -Fq "$DART_VERSION" "$file"; then
    fail "pinned version literal duplicated in ${file#"$repo_root/"}"
  fi
done < <(
  find "$repo_root" -type f \
    -not -path '*/.git/*' \
    -not -path '*/.dart_tool/*' \
    -not -path '*/build/*' \
    -not -name '.flutter-plugins-dependencies'
)

printf 'Toolchain configuration is consistent.\n'
