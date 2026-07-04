#!/usr/bin/env sh
#
# strip-enterprise.sh <checkout-dir>
#
# Bulk-remove the proprietary tree, the symlink into it, and the second copy
# under tests/. This is intentionally not a patch: a diff that deletes hundreds
# of files is unreadable and drifts on every upstream release.
#
set -eu

root="${1:?usage: strip-enterprise.sh <checkout-dir>}"

if [ ! -d "$root" ]; then
    printf 'strip-enterprise: %s is not a directory\n' "$root" >&2
    exit 1
fi

rm -rf "$root/enterprise"
rm -f  "$root/litellm/proxy/enterprise"        # dangling symlink into ../../enterprise
rm -rf "$root/tests/enterprise"

# Commit the removals so `git apply --3way` on the patch series has a clean
# working tree to operate against.
if [ -d "$root/.git" ]; then
    git -C "$root" add -A
    git -C "$root" -c user.email=libre@localhost -c user.name=libre \
        commit -q -m 'strip: remove enterprise/, symlink, tests/enterprise/'
fi

printf 'strip-enterprise: removed enterprise/, litellm/proxy/enterprise, tests/enterprise/\n'
