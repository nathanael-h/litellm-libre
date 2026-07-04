#!/usr/bin/env sh
#
# verify.sh <checkout-dir>
#
# Smoke-tests a stripped+patched checkout. Runs three checks:
#   1. The removed paths really are gone.
#   2. No unguarded top-level litellm_enterprise import survived in litellm/.
#   3. `python -c "import litellm"` and `python litellm/proxy/proxy_cli.py --help`
#      both exit 0 in a uv-managed environment.
#
# The proxy boot + curl smoke test is intentionally scoped to build-release.yml,
# which has real credentials.
#
set -eu

root="${1:?usage: verify.sh <checkout-dir>}"
cd "$root"

fail() { printf 'verify: FAIL: %s\n' "$1" >&2; exit 1; }

for path in enterprise litellm/proxy/enterprise tests/enterprise; do
    if [ -e "$path" ] || [ -L "$path" ]; then
        fail "$path still present after strip"
    fi
done

if grep -rnE '^(from|import) litellm_enterprise' litellm/ >/tmp/libre-unguarded.txt; then
    printf 'verify: unguarded litellm_enterprise imports found in litellm/:\n' >&2
    cat /tmp/libre-unguarded.txt >&2
    fail 'unguarded enterprise imports'
fi

if grep -rnE 'billable_users.*>' litellm/proxy/management_endpoints/ui_sso.py; then
    fail 'SSO user-count gate is still present in ui_sso.py'
fi

# Runtime checks. Use uv if available; fall back to plain python.
# litellm does not expose litellm.__version__; the installed version lives in
# package metadata. Assert the module imports and report the metadata version.
ver_check='import litellm, importlib.metadata as m; print("litellm", m.version("litellm"))'
if command -v uv >/dev/null 2>&1; then
    uv sync --frozen --no-install-workspace --extra proxy --python python3
    uv run python -c "$ver_check"
    uv run python litellm/proxy/proxy_cli.py --help >/dev/null
else
    python -c "$ver_check"
    python litellm/proxy/proxy_cli.py --help >/dev/null
fi

printf 'verify: OK\n'
