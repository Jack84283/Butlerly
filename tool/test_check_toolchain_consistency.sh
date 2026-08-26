#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "$repo_root/tool/toolchain.env"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/.github/actions/setup-toolchain" \
  "$fixture/.github/workflows" \
  "$fixture/apps/butlerly/android" \
  "$fixture/config" \
  "$fixture/tool"
cp "$repo_root/tool/check_toolchain_consistency.sh" "$fixture/tool/"
cp "$repo_root/tool/toolchain.env" "$fixture/tool/"
cat >"$fixture/tool/test_verify_toolchain.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture/tool/"*.sh
cat >"$fixture/.github/workflows/ci.yml" <<'EOF'
uses: ./.github/actions/setup-toolchain
run: ./tool/setup.sh
run: ./tool/validate.sh
EOF
cat >"$fixture/.github/actions/setup-toolchain/action.yml" <<'EOF'
runs:
  steps:
    - run: source tool/toolchain.env && ./tool/verify_toolchain.sh
EOF
printf 'flutter.sdk=/opt/flutter/%s\n' "$FLUTTER_VERSION" \
  >"$fixture/apps/butlerly/android/local.properties"

git -C "$fixture" init -q
git -C "$fixture" add .
BUTLERLY_SKIP_CONSISTENCY_REGRESSION=1 \
  "$fixture/tool/check_toolchain_consistency.sh" >/dev/null

printf 'flutter_version: %s\n' "$FLUTTER_VERSION" >"$fixture/config/toolchain.yml"
git -C "$fixture" add config/toolchain.yml
if BUTLERLY_SKIP_CONSISTENCY_REGRESSION=1 \
  "$fixture/tool/check_toolchain_consistency.sh" >/dev/null 2>&1; then
  printf 'error: tracked configuration containing a duplicate pin was accepted\n' >&2
  exit 1
fi

printf 'Toolchain generated-file regression checks passed.\n'
