---
name: Patch drift
about: A libre patch failed to apply against a new upstream tag
title: "patch drift: build failed at <upstream-tag>"
labels: patch-drift
---

## Upstream tag

`v<major>.<minor>.<patch>-stable`

## What failed

Pipeline step (fetch / strip / apply / verify / build):

## Reject hunks or build log tail

<details>
<summary>rejects</summary>

```
<paste the .rej files from build/.libre-rejects/ or the failing log tail>
```

</details>

## Suggested action

- If the failure is in `apply`, trigger `ai-fix.yml` with the upstream tag and
  the failing patch filename, then review the PR it opens.
- If the failure is in `verify` (e.g. an unguarded `litellm_enterprise` import
  showed up upstream), investigate manually before regenerating patches, since
  it usually means a runtime dependency needs guarding on the upstream side.
- If the failure is in `build`, capture the last ~200 lines of the uv/docker
  log and comment them here before dispatching `ai-fix.yml`.
