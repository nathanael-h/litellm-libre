#!/usr/bin/env sh
#
# apply-patches.sh <checkout-dir> [<patches-dir>]
#
# Applies each patch in <patches-dir>/series (default: ../patches relative to
# this script) with `git apply --3way`. On failure it writes diagnostics under
# <checkout-dir>/.libre-rejects/ and exits non-zero so the CI job can publish
# them to the drift issue:
#
#   apply-failure.log  - which patch failed, the `git apply --3way` stderr, and
#                        (from a `--reject` retry) a summary of hunk offsets.
#   *.rej              - the individual rejected hunks (materialized by the
#                        `--reject` retry; `git apply --3way` alone leaves none).
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

# Capture the apply stderr outside $root so it never gets swept into `git add`.
apply_err="$(mktemp "${TMPDIR:-/tmp}/libre-apply.XXXXXX")"
trap 'rm -f "$apply_err"' EXIT

failed=""
while IFS= read -r patch; do
    case "$patch" in ''|\#*) continue ;; esac
    printf 'apply-patches: applying %s\n' "$patch"
    if ! git -C "$root" apply --3way --whitespace=nowarn "$patches_dir/$patch" 2>"$apply_err"; then
        cat "$apply_err" >&2 || true
        failed="$patch"
        break
    fi
    git -C "$root" add -A
    git -C "$root" -c user.email=libre@localhost -c user.name=libre \
        commit -q -m "libre: $patch"
done < "$patches_dir/series"

if [ -n "$failed" ]; then
    mkdir -p "$rej_dir"

    # `git apply --3way` does not leave .rej files (only GNU patch does), so the
    # only real diagnostics are on stderr. Record them, then retry with
    # --reject to materialize the individual rejected hunks for inspection.
    {
        printf 'Failed patch: %s\n' "$failed"
        printf 'Applied cleanly before it: %s\n\n' "$(git -C "$root" log --format='%s' | sed -n 's/^libre: //p' | paste -sd', ' - || true)"
        printf '=== git apply --3way stderr ===\n'
        cat "$apply_err" 2>/dev/null || true
        printf '\n=== git apply --reject (hunk-level) ===\n'
    } > "$rej_dir/apply-failure.log"
    git -C "$root" apply --reject --whitespace=nowarn "$patches_dir/$failed" \
        >> "$rej_dir/apply-failure.log" 2>&1 || true

    # Collect the .rej hunks the --reject retry dropped next to their targets.
    find "$root" -name '*.rej' -not -path "$rej_dir/*" | while IFS= read -r r; do
        rel="${r#"$root"/}"
        target="$rej_dir/$rel"
        mkdir -p "$(dirname "$target")"
        cp "$r" "$target"
    done

    printf 'apply-patches: failed on %s; diagnostics in %s\n' "$failed" "$rej_dir" >&2
    exit 2
fi

printf 'apply-patches: all patches applied cleanly\n'
