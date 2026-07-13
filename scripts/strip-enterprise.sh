#!/usr/bin/env sh
#
# strip-enterprise.sh <checkout-dir>
#
# De-proprietarizes an upstream checkout so the rest of the pipeline can build a
# libre artifact. Two kinds of edits, both deliberately NOT patches:
#
#   1. Bulk file/dir removals: the enterprise/ tree, the symlink into it, and the
#      second copy under tests/. A diff deleting hundreds of files is unreadable.
#   2. pyproject.toml packaging edits: drop the litellm-enterprise dependency,
#      its uv workspace source + member, and its source-exclude entry.
#
# (2) used to be patch 0001, but that carried the exact dependency versions
# (litellm-enterprise==X.Y.Z, and the adjacent litellm-proxy-extras==X.Y.Z
# context line) which upstream bumps almost every weekly release, so the patch
# drifted and failed to apply constantly. The edits here match by PATTERN, not
# version, so they survive routine version bumps. They still fail loudly (see the
# assertions) if upstream restructures the file so an anchor disappears.
#
set -eu

root="${1:?usage: strip-enterprise.sh <checkout-dir>}"

if [ ! -d "$root" ]; then
    printf 'strip-enterprise: %s is not a directory\n' "$root" >&2
    exit 1
fi

fail() { printf 'strip-enterprise: FAIL: %s\n' "$1" >&2; exit 1; }

# --- 1. Bulk removals ------------------------------------------------------
rm -rf "$root/enterprise"
rm -f  "$root/litellm/proxy/enterprise"        # dangling symlink into ../../enterprise
rm -rf "$root/tests/enterprise"

# --- 2. pyproject.toml packaging edits (version-independent) ---------------
pyproject="$root/pyproject.toml"
[ -f "$pyproject" ] || fail "$pyproject not found"

# Drop the runtime dependency line, e.g.  "litellm-enterprise==0.1.44",
sed -i -E '/^[[:space:]]*"litellm-enterprise[^"]*",?[[:space:]]*$/d' "$pyproject"
# Drop the uv workspace source:  litellm-enterprise = { workspace = true }
sed -i -E '/^[[:space:]]*litellm-enterprise[[:space:]]*=[[:space:]]*\{[^}]*workspace[^}]*\}[[:space:]]*$/d' "$pyproject"
# Drop "enterprise" from the uv workspace members array (whether first or last).
sed -i -E '/^[[:space:]]*members[[:space:]]*=/{ s/"enterprise",[[:space:]]*//; s/,[[:space:]]*"enterprise"//; }' "$pyproject"
# Drop the source-exclude entry for the (now deleted) enterprise proxy tree.
sed -i -E '/^[[:space:]]*"litellm\/proxy\/enterprise",?[[:space:]]*$/d' "$pyproject"

# Assert the result, not that we changed something: if upstream ever ships
# without the enterprise bits these are no-ops and that's fine; what must never
# happen is an enterprise reference surviving into the libre build.
grep -q 'litellm-enterprise' "$pyproject" \
    && fail 'litellm-enterprise still referenced in pyproject.toml after edits (upstream layout changed?)'
grep -qE '^[[:space:]]*members[[:space:]]*=.*"enterprise"' "$pyproject" \
    && fail 'enterprise still listed as a uv workspace member in pyproject.toml'
grep -q '"litellm/proxy/enterprise"' "$pyproject" \
    && fail 'litellm/proxy/enterprise still in source-exclude in pyproject.toml'

# Commit the changes so `git apply --3way` on the patch series has a clean
# working tree to operate against.
if [ -d "$root/.git" ]; then
    git -C "$root" add -A
    git -C "$root" -c user.email=libre@localhost -c user.name=libre \
        commit -q -m 'strip: remove enterprise/ tree, symlink, tests copy, and pyproject refs'
fi

printf 'strip-enterprise: removed enterprise tree + de-enterprised pyproject.toml\n'
