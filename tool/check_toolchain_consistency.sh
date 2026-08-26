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
if [[ "${BUTLERLY_SKIP_CONSISTENCY_REGRESSION:-}" != 1 ]]; then
  "$repo_root/tool/test_check_toolchain_consistency.sh"
fi

if grep -Eq 'channel:[[:space:]]*stable|sdk:[[:space:]]*stable' "$workflow"; then
  fail 'CI must not select a floating stable SDK'
fi

if grep -Eq 'dart (format|analyze|test)|flutter (analyze|test|build web)' "$workflow"; then
  fail 'canonical validation commands must remain in tool/validate.sh, not CI'
fi

while IFS= read -r -d '' relative_file; do
  case "$relative_file" in
    tool/toolchain.env | apps/butlerly/android/local.properties)
      continue
      ;;
  esac
  file="$repo_root/$relative_file"
  if grep -Fq "$FLUTTER_VERSION" "$file" || grep -Fq "$DART_VERSION" "$file"; then
    fail "pinned version literal duplicated in $relative_file"
  fi
done < <(
  git -C "$repo_root" ls-files -z
)

printf 'Toolchain configuration is consistent.\n'
