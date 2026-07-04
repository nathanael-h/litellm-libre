# litellm-libre: a FLOSS distribution of LiteLLM

A plan for a small, standalone repository that produces a fully libre (MIT-only) build of
[BerriAI/litellm](https://github.com/BerriAI/litellm) by stripping the proprietary
`enterprise/` code, and keeps that build current automatically as upstream releases.

This document is both the design and the running context of the decision. Read the
"Context and findings" section first if you're new to the problem.

## Goal

Ship a build of LiteLLM that contains no proprietary code, tracks upstream `-stable`
releases with minimal manual effort, and stays auditable. We do not hard-fork the source.
We keep a tiny, rebasable patch set plus a bulk-removal step, apply it onto each upstream
release, then build and publish.

## Context and findings (why this design)

These were established by inspecting the current fork at version `1.92.0`.

The MIT-licensed core is designed to run without the enterprise package. All 36
`litellm_enterprise` import sites across 16 files in `litellm/` are guarded (inside
`try/except` or lazy function-level imports); there are zero unguarded module-scope
imports. So removing the proprietary package degrades enterprise features to no-ops rather
than crashing. Removal is the intended path, not a hack.

The enterprise code carried its own proprietary license, distinct from the MIT core. We may
drop it but not relicense it, so a libre distribution must exclude it from the build
artifact, not just leave it dormant.

What actually breaks when `enterprise/` is gone is packaging and image builds, not runtime:

- `pyproject.toml:66` declares `"litellm-enterprise==0.1.46"` as a hard runtime dependency
- `pyproject.toml:256` `litellm-enterprise = { workspace = true }` and `:259`
  `members = ["enterprise", "litellm-proxy-extras"]` reference the deleted dir, so
  `uv sync` / build fails
- `pyproject.toml:264` `source-exclude` lists `litellm/proxy/enterprise`
- `litellm/proxy/enterprise` is a symlink to `../../enterprise` (dangles once removed)
- `Dockerfile`, `docker/Dockerfile.database`, `docker/Dockerfile.non_root` each
  `COPY enterprise/pyproject.toml` and `COPY --from=builder /app/enterprise /app/enterprise`
- `docker/build_admin_ui.sh:12` reads `enterprise/enterprise_ui/enterprise_colors.json`
- `tests/enterprise/litellm_enterprise/` is a second full copy of the enterprise code

Upstream releases very frequently (~every 17h across dev/rc/stable). The load-tested
`-stable` tags are the sane track to follow, roughly weekly, instead of chasing every dev
tag.

No usable existing libre fork exists. The only candidate, `jmikedupont2/openlightllm`, still
ships the full `enterprise/` tree, strips nothing, and doesn't track upstream. So we build
our own thin layer rather than adopt someone else's hard fork.

There is also a product decision embedded here: the SSO "free tier" gate in
`litellm/proxy/management_endpoints/ui_sso.py` refuses SSO for more than N users unless a
license is set. In a FLOSS build that gate should be removed entirely (see patch 0004).

## Repository layout

A new standalone repo, `litellm-libre`, that contains no LiteLLM source. It carries only
patches, scripts, workflows, and docs.

```
litellm-libre/
├── README.md                      # what this is, how to build locally, licensing note
├── PLAN.md                        # this document (design + context)
├── UPSTREAM                       # single line: the last upstream tag we built, e.g. v1.92.0-stable
├── patches/
│   ├── series                     # ordered list of patches to apply
│   ├── 0001-pyproject-drop-enterprise.patch
│   ├── 0002-dockerfiles-drop-enterprise.patch
│   ├── 0003-build-admin-ui-drop-enterprise.patch
│   └── 0004-remove-sso-user-gate.patch
├── scripts/
│   ├── fetch-upstream.sh          # clone/checkout a given upstream tag into ./build
│   ├── strip-enterprise.sh        # bulk file/dir removals (rm the tree, symlink, tests copy)
│   ├── apply-patches.sh           # git apply --3way each patch in series; collect rejects
│   ├── build.sh                   # uv build (wheel+sdist) and docker build
│   └── verify.sh                  # smoke test: import litellm, boot proxy --help, run a curl
└── .github/
    ├── ISSUE_TEMPLATE/
    │   └── patch-drift.md
    └── workflows/
        ├── watch-upstream.yml     # scheduled: detect new -stable tag, dispatch build
        ├── build-release.yml      # apply patches, build, publish; open issue on failure
        └── ai-fix.yml             # manual/dispatch: LLM-assisted patch refresh -> PR
```

Rationale for patches-onto-checkout rather than a fork branch: the lite repo stays tiny and
every deviation from upstream is a reviewable `.patch` file. Bulk deletions (the whole
`enterprise/` tree, the symlink, the `tests/enterprise/` copy) are done by
`strip-enterprise.sh` rather than a giant patch, because a patch that deletes hundreds of
files is unreadable and brittle. Patches are reserved for the small, semantically meaningful
text edits.

## The patch set

Four patches plus one removal script. Text edits below are the exact current lines, so the
patches are ready to author.

### strip-enterprise.sh (removals, not a patch)

```sh
#!/usr/bin/env sh
set -eu
root="${1:?usage: strip-enterprise.sh <checkout-dir>}"
rm -rf   "$root/enterprise"
rm -f    "$root/litellm/proxy/enterprise"      # dangling symlink
rm -rf   "$root/tests/enterprise"
```

`verify.sh` should assert none of these paths exist afterward and that
`grep -rn "^from litellm_enterprise\|^import litellm_enterprise" "$root/litellm/"` is empty
(guarding against upstream adding a new unguarded import).

### 0001-pyproject-drop-enterprise.patch

Remove the dependency, the workspace source, the workspace member, and the source-exclude
entry.

- delete line 66: `"litellm-enterprise==0.1.46",`
- delete line 256: `litellm-enterprise = { workspace = true }`
- change line 259: `members = ["enterprise", "litellm-proxy-extras"]`
  to `members = ["litellm-proxy-extras"]`
- delete line 264: `"litellm/proxy/enterprise",` from `source-exclude`

### 0002-dockerfiles-drop-enterprise.patch

In each of `Dockerfile`, `docker/Dockerfile.database`, `docker/Dockerfile.non_root`, remove
the `COPY enterprise/pyproject.toml enterprise/` line and the
`COPY --from=builder /app/enterprise /app/enterprise` line.

### 0003-build-admin-ui-drop-enterprise.patch

In `docker/build_admin_ui.sh`, drop the branch that requires
`enterprise/enterprise_ui/enterprise_colors.json` (fall back to the default colors that the
OSS UI already ships).

### 0004-remove-sso-user-gate.patch (the FLOSS SSO patch)

In `litellm/proxy/management_endpoints/ui_sso.py`, remove both `premium_user` gates that
otherwise refuse SSO in a FLOSS build:

1. The "free SSO user limit" block in `google_login` (currently lines ~856-875): the
   `billable_users` count, the `> N` raise, and the `db_not_connected` raise that only
   exists to power that gate. This supersedes the interim `5 -> 5000` bump; the gate
   goes away entirely.
2. The equivalent block in `debug_sso_login` (currently lines ~4116-4130): the `from
   litellm.proxy.proxy_server import premium_user` import and the
   `if microsoft_client_id ... premium_user is not True: raise ...` that mirrors the
   first gate for the debug endpoint.

The patch should delete both gates and leave the surrounding SSO flow (redirect URL,
CLI source handling) intact. Other in-proxy `premium_user` references that pass the
flag downstream (e.g. into key generation) are left alone; they are not user-facing
gates.

## Versioning and artifacts

Version scheme mirrors upstream with a libre suffix: upstream `v1.92.0-stable` becomes
`1.92.0+libre.1` (or `-libre.1` if the target index rejects local-version segments). The
`+libre.N` counter increments only when we change patches for the same upstream version.

Artifacts published per release:

- Python wheel + sdist to GitHub Releases (optionally a separately named PyPI package, e.g.
  `litellm-libre`, never reusing the upstream `litellm` name on PyPI)
- Docker image to GHCR, tags `:1.92.0-libre`, `:latest`, `:stable`

## Workflows

### watch-upstream.yml (scheduled detector)

Runs on a cron (e.g. every 6h). Queries the GitHub API for the latest upstream tag matching
`v*-stable`, compares it to the `UPSTREAM` file. If newer, it commits the new tag to
`UPSTREAM` on a branch and dispatches `build-release.yml` with that tag as input. No
`curl | bash`; use `gh api` or `actions/github-script`.

### build-release.yml (the pipeline)

Inputs: upstream tag. Steps:

1. `scripts/fetch-upstream.sh <tag>` -> checkout into `./build`
2. `scripts/strip-enterprise.sh ./build`
3. `scripts/apply-patches.sh ./build` (uses `git apply --3way`; on any reject, stop and
   fail with the collected `.rej` content captured as a job output)
4. `scripts/verify.sh ./build` (import + `proxy_cli.py --help` + a real curl smoke test
   against a booted proxy)
5. `scripts/build.sh` (uv build + docker build)
6. publish artifacts, then update `UPSTREAM` and tag the lite release

On failure at step 3 or later, an `on: failure` job opens (or updates) a GitHub issue using
the `patch-drift.md` template, labeled `patch-drift`, containing the upstream tag, which step
failed, and the reject hunks or build log tail. This is the signal for a human to trigger the
AI fix.

### ai-fix.yml (semi-manual LLM patch refresh)

Triggered manually (`workflow_dispatch`) or by commenting a command on the drift issue, not
automatically merged. It feeds the failing patch, the `.rej` hunks, and the relevant upstream
files at the new tag to an LLM (Claude Code action or an API step), asks it to regenerate the
patch against the new upstream, re-runs `apply-patches.sh` + `verify.sh`, and if green opens
a PR updating the patch file. A maintainer reviews and merges. "Semi-manual" is deliberate:
the model proposes, a human approves, because patch drift on security-relevant gates (auth,
SSO) must not auto-merge.

## Failure modes to design for

Patch context drift is the common one; `--3way` absorbs small moves, rejects surface the
rest to `ai-fix.yml`. Upstream adding a new unguarded `litellm_enterprise` import would break
runtime silently, so `verify.sh` greps for that explicitly and fails loudly. Upstream renaming
the enterprise dir or the SSO gate would fail `apply-patches.sh` cleanly and route to the
drift issue. A silently successful build that still bundles enterprise code is caught by
`verify.sh` asserting the removed paths are absent.

## Milestones

1. Author the four patches and `strip-enterprise.sh` against `v1.92.0-stable`; get a clean
   local `uv build` and a booting proxy verified with a real curl.
2. Add `fetch/apply/build/verify` scripts and `build-release.yml`; cut the first lite release
   by hand-dispatch.
3. Add `watch-upstream.yml` and the drift issue flow; confirm it opens an issue on a
   deliberately broken patch.
4. Add `ai-fix.yml` and dry-run it against a real drift.
5. Write `README.md` (what it is, MIT-only guarantee, how to install the wheel / pull the
   image, how the update loop works) and finalize licensing notes.

## Open questions for the maintainer

- PyPI: publish under a distinct name, or GitHub Releases + GHCR only?
- Which upstream track: `-stable` only (recommended), or also `-rc`?

The earlier question about dropping other `premium_user` checks has been answered:
patch 0004 now removes both SSO-facing `premium_user` gates in `ui_sso.py`.
The remaining `premium_user` references in the proxy pass the flag through to
downstream helpers (key generation, team scoping) and are not user-facing gates,
so they stay.
