#!/usr/bin/env sh
#
# ai-fix.sh <upstream-tag> <failing-patch>
#
# Regenerate a single failing patch against a newer upstream tag by driving
# the Claude Code CLI (`claude -p ...`) in print mode. Runs identically on a
# laptop and in CI; the GitHub workflow just calls this script.
#
# Requirements:
#   - `claude` on PATH (Claude Code CLI)
#   - ANTHROPIC_API_KEY exported (unless you've already run `claude login`)
#   - git, and whatever `scripts/verify.sh` needs (uv, python)
#
# Usage:
#   scripts/ai-fix.sh v1.93.0-stable 0004-remove-sso-user-gate.patch
#
# What it does:
#   1. Fetches the upstream tag into ./build via scripts/fetch-upstream.sh
#   2. Strips the enterprise tree
#   3. Applies patches in series *up to but not including* the failing patch,
#      so Claude sees the same base state the failure would have hit.
#   4. Invokes Claude with a scoped prompt that asks it to rewrite
#      patches/<failing-patch> against the new upstream.
#   5. Restores patches/series and runs the full pipeline against a fresh
#      ./build2 checkout to confirm the regenerated patch applies and
#      verify.sh passes end to end.
#   6. Leaves the diff in patches/<failing-patch> for you to review + commit.
#      Nothing is committed automatically.
#
set -eu

tag="${1:?usage: ai-fix.sh <upstream-tag> <failing-patch>}"
failing="${2:?usage: ai-fix.sh <upstream-tag> <failing-patch>}"

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
series="$root/patches/series"
patch_file="$root/patches/$failing"

if [ ! -f "$patch_file" ]; then
    printf 'ai-fix: no such patch: %s\n' "$patch_file" >&2
    exit 1
fi

if ! grep -qxF "$failing" "$series"; then
    printf 'ai-fix: patch %s is not in patches/series\n' "$failing" >&2
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    printf 'ai-fix: `claude` CLI not found. Install Claude Code and set ANTHROPIC_API_KEY.\n' >&2
    exit 1
fi

work="$root/build"
final="$root/build2"
if [ -e "$work" ] || [ -e "$final" ]; then
    printf 'ai-fix: %s or %s already exists; remove them first\n' "$work" "$final" >&2
    exit 1
fi

cleanup() {
    if [ -f "$series.bak" ]; then
        mv "$series.bak" "$series"
    fi
}
trap cleanup EXIT INT TERM

"$here/fetch-upstream.sh" "$tag" "$work"
"$here/strip-enterprise.sh" "$work"

# Apply everything in the series before the failing patch so Claude sees the
# same base state the pipeline would have hit at the point of failure.
cp "$series" "$series.bak"
awk -v stop="$failing" '
    /^[[:space:]]*(#|$)/ { print; next }
    $0 == stop { exit }
    { print }
' "$series.bak" > "$series"

"$here/apply-patches.sh" "$work"

# Restore the full series before Claude runs, so the model sees the intended
# ordering when it reads patches/series (some models cross-reference it).
mv "$series.bak" "$series"

prompt=$(cat <<PROMPT
You are refreshing a single patch in the litellm-libre repository against a
new upstream LiteLLM release.

Repo root:     $root
Upstream tag:  $tag
Failing patch: patches/$failing
Upstream code: $work/  (already stripped of enterprise/ and with the
               preceding patches in patches/series already applied)

Your job:

1. Read the current patch at patches/$failing and PLAN.md. Understand the
   semantic change the patch is supposed to make (each patch maps to a
   section in PLAN.md under "The patch set"). Do not rely on line numbers;
   rely on the intent.

2. Read the corresponding upstream file(s) inside $work/ at the new tag.
   Reproduce the same semantic change against those files. Use the Edit
   tool inside $work/ freely; the goal is to get the working tree to the
   state the patch is supposed to produce.

3. Once $work/ is in the desired state, capture the resulting diff:
       git -C $work diff --patch <path...> > $root/patches/$failing
   Overwrite the existing patch file. Do not include any file that the
   patch was not originally intended to touch.

4. Do NOT touch any file outside $root/patches/$failing. Do not modify the
   other patches, the scripts, or the workflows. Do not weaken the SSO or
   license gates beyond what the original patch already removed. If the
   upstream diff makes the original intent unreachable (e.g. the whole
   code path is gone), stop and print an explanation instead of writing a
   patch.

5. After you are done, print a two-line summary: what changed in the patch,
   and any risks you saw. Do not run verify.sh yourself; the caller will.
PROMPT
)

printf 'ai-fix: invoking claude to regenerate patches/%s\n' "$failing"
claude -p "$prompt"

# Fresh end-to-end run against a clean checkout to confirm the regenerated
# patch applies and verify.sh passes.
rm -rf "$work"
"$here/fetch-upstream.sh" "$tag" "$final"
"$here/strip-enterprise.sh" "$final"
"$here/apply-patches.sh" "$final"
"$here/verify.sh" "$final"

printf '\nai-fix: SUCCESS\n'
printf 'ai-fix: regenerated patch is at patches/%s\n' "$failing"
printf 'ai-fix: fresh verified checkout is at %s (safe to remove when done)\n' "$final"
printf 'ai-fix: review the diff, then commit and push manually\n'
