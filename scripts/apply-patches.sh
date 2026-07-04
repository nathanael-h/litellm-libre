#!/usr/bin/env sh
#
# apply-patches.sh <checkout-dir> [<patches-dir>]
#
# Applies each patch in <patches-dir>/series (default: ../patches relative to
# this script) with `git apply --3way`. On failure, collects any .rej hunks
# under <checkout-dir>/.libre-rejects/ and exits non-zero so the CI job can
# publish the reject content to the drift issue.
#
set -eu

root="${1:?usage: apply-patches.sh <checkout-dir> [<patches-dir>]}"
here="$(cd "$(dirname "$0")" && pwd)"
patches_dir="${2:-$here/../patches}"

if [ ! -f "$patches_dir/series" ]; then
    printf 'apply-patches: no series file at %s/series\n' "$patches_dir" >&2
    exit 1
fi

rej_dir="$root/.libre-rejects"
rm -rf "$rej_dir"

failed=""
while IFS= read -r patch; do
    case "$patch" in ''|\#*) continue ;; esac
    printf 'apply-patches: applying %s\n' "$patch"
    if ! git -C "$root" apply --3way --whitespace=nowarn "$patches_dir/$patch"; then
        failed="$patch"
        break
    fi
    git -C "$root" add -A
    git -C "$root" -c user.email=libre@localhost -c user.name=libre \
        commit -q -m "libre: $patch"
done < "$patches_dir/series"

if [ -n "$failed" ]; then
    mkdir -p "$rej_dir"
    # git apply --3way leaves .rej alongside the target file
    find "$root" -name '*.rej' -not -path "$rej_dir/*" | while IFS= read -r r; do
        rel="${r#$root/}"
        target="$rej_dir/$rel"
        mkdir -p "$(dirname "$target")"
        cp "$r" "$target"
    done
    printf 'apply-patches: failed on %s; rejects in %s\n' "$failed" "$rej_dir" >&2
    exit 2
fi

printf 'apply-patches: all patches applied cleanly\n'
