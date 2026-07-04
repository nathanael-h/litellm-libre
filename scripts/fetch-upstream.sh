#!/usr/bin/env sh
#
# fetch-upstream.sh <tag> [<dest>]
#
# Shallow-clone https://github.com/BerriAI/litellm at the given tag into <dest>
# (default: ./build). Initializes a local branch so subsequent `git apply --3way`
# has an index to merge against.
#
set -eu

tag="${1:?usage: fetch-upstream.sh <upstream-tag> [<dest>]}"
dest="${2:-./build}"
repo_url="${LITELLM_UPSTREAM_URL:-https://github.com/BerriAI/litellm.git}"

if [ -e "$dest" ]; then
    printf 'fetch-upstream: destination %s already exists; refusing to overwrite\n' "$dest" >&2
    exit 1
fi

git clone --depth 1 --branch "$tag" --single-branch "$repo_url" "$dest"

# Detach and re-anchor so `git apply --3way` has a stable base to merge against
# and downstream tooling (verify.sh) doesn't confuse the upstream branch name
# for our own working state.
git -C "$dest" checkout --detach
git -C "$dest" checkout -b libre-work

printf 'fetch-upstream: checked out %s at %s into %s\n' "$repo_url" "$tag" "$dest"
