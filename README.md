# litellm-libre

A fully libre (MIT-only) build of [BerriAI/litellm](https://github.com/BerriAI/litellm)
produced by stripping the proprietary `enterprise/` tree from each upstream
`-stable` release and reapplying a small, rebasable patch set on top.

This repository contains no LiteLLM source; only patches, scripts, workflows,
and docs. Each release cycle checks out the tag pinned in [`UPSTREAM`](UPSTREAM),
runs [`scripts/strip-enterprise.sh`](scripts/strip-enterprise.sh) to delete the
proprietary tree and the symlink into it, then applies the ordered patch series
under [`patches/`](patches/) before building.

See [`PLAN.md`](PLAN.md) for the full design and the rationale behind each
patch.

## What the libre build changes

1. Deletes `enterprise/`, the `litellm/proxy/enterprise` symlink into it, and
   the second copy under `tests/enterprise/`.
2. Removes the `litellm-enterprise` workspace member, the pinned dependency,
   and the source-exclude entry from `pyproject.toml`.
3. Drops the `COPY enterprise/...` layers from every Dockerfile so the images
   build from a tree that does not contain the proprietary source.
4. Turns `docker/build_admin_ui.sh` into a no-op stub that always uses the
   default OSS UI (no enterprise color override).
5. Removes the "free SSO user limit" gate in
   `litellm/proxy/management_endpoints/ui_sso.py`. A FLOSS build must not cap
   SSO by user count. The other `premium_user` checks in the proxy are left
   in place (see the "Open questions" section of `PLAN.md`).

All 36 `litellm_enterprise` import sites in `litellm/` are already guarded
(inside `try/except` or lazy function-scope imports) upstream, so removing the
proprietary package degrades enterprise features to no-ops rather than
crashing. `verify.sh` guards against upstream ever adding a new unguarded
import.

## Local build

```sh
scripts/fetch-upstream.sh "$(cat UPSTREAM)"
scripts/strip-enterprise.sh ./build
scripts/apply-patches.sh ./build
scripts/verify.sh ./build
scripts/build.sh ./build "1.92.0+libre.1"   # optional version arg
```

Artifacts land in `./build/dist/`. Pass `BUILD_DOCKER=1 scripts/build.sh ...`
to also produce a `litellm-libre:<version>` image.

## Update loop

Automated end-to-end:

1. [`watch-upstream.yml`](.github/workflows/watch-upstream.yml) runs on a cron
   and dispatches `build-release.yml` when a new `v*-stable` tag appears.
2. [`build-release.yml`](.github/workflows/build-release.yml) applies the
   patch series, verifies, builds wheel + sdist + Docker image, publishes to
   the GitHub Release and to GHCR, and updates `UPSTREAM`.
3. If a patch fails to apply cleanly, the workflow opens (or updates) a
   `patch-drift` issue with the reject hunks.
4. A maintainer runs [`scripts/ai-fix.sh`](scripts/ai-fix.sh) with the
   upstream tag and failing patch filename. The script drives the Claude
   Code CLI (`claude -p ...`) to regenerate the patch against the new
   upstream, then re-runs the full pipeline against a fresh checkout to
   confirm the patch applies and `verify.sh` passes. The regenerated diff
   is left in `patches/` for review; nothing is committed automatically.

   The GitHub workflow [`ai-fix.yml`](.github/workflows/ai-fix.yml) is the
   same script wrapped in a `workflow_dispatch` trigger; it installs the
   Claude Code CLI, invokes `scripts/ai-fix.sh`, then opens a PR with the
   regenerated patch. Merging is manual; patch drift on auth-adjacent
   gates must not auto-merge.

### Running `ai-fix.sh` on a laptop

```sh
export ANTHROPIC_API_KEY=sk-ant-...      # or run `claude login` once
scripts/ai-fix.sh v1.93.0-stable 0004-remove-sso-user-gate.patch
```

Prerequisites: the [Claude Code CLI](https://github.com/anthropics/claude-code)
on `PATH` (`npm install -g @anthropic-ai/claude-code`), plus whatever
`verify.sh` needs (uv + a Python interpreter). The script never touches your
main working tree; all work happens under `./build/` and `./build2/`, which
are gitignored.

## Licensing

The libre distribution consists exclusively of MIT-licensed LiteLLM source
after `strip-enterprise.sh` runs. This repository itself (patches, scripts,
workflows, docs) is MIT-licensed. The proprietary `enterprise/` tree is
excluded from every build artifact.
