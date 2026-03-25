---
name: people-jira-branch-setup
description: >-
  People Data squad — ensure Jira issue exists, branch naming, sync from
  origin/master, local branch only (remote sync out of scope here). Invoke when
  beginning ticketed work on bi-etl-ejuice.
---

# People Data — Jira issue and branch setup

**Before Jira/MCP or Git branch steps:** Read **[`dbp-jira-reference.md`](../../../rules/people/dbp-jira-reference.md)** (kickoff policies, **Sprints and buffer (DBP)**, language, branch/slug/Jira summary, API quirks, workflow). **Buffer vs planned** sprint work is defined there — **confirm with the user**; do not guess. **Artifact paths:** **[`people_domain.mdc`](../../../rules/people/people_domain.mdc)** — **Delivery artifact folder (`.cursor/temp/`)**. Extend the reference when you learn new durable Jira facts.

Use this skill when starting **non–local-only** work on `bi-etl-ejuice`. If **local-only**, see **Kickoff policies** in the reference (skip this workflow unless asked).

## Quick path (happy path)

- Confirm or create the **right** Jira issue; move to **start-of-coding** (**Delivery hints** in the reference).
- Resolve **branch key** and **slug** per **Branch, slug, and Jira summary** in the reference (most specific `{KEY}`).
- Reuse or create **`{KEY}/{slug}`** from updated **`origin/master`** (or `origin/HEAD` — see §3); keep work **local** until a later step updates the remote.
- Ensure **`.cursor/temp/`** mirrors the branch (**Delivery artifact folder** in **`people_domain.mdc`**).

## Workflow

### 1. Jira

- **No issue yet:** After user approval, propose **Story** or **Sub-task** per **Kickoff policies** and **API and automation quirks** in the reference; create/update via Atlassian MCP (**MCP (Cursor workspace)** there).
- **Status:** Transition per **Delivery hints** / **Workflow snapshot** in the reference. If transition names/ids are unknown, use the tool that lists transitions (see reference). If blocked, **Jira comment** + user acceptance before continuing.

### 2. Git — existing branch

- If the current branch already matches **`{KEY}/...`** for the **same** key (most specific), do **not** force a new branch — confirm continue vs recreate.
- List branches containing that key; ask **reuse** vs **create new**.

### 3. Git — base and new branch

- **Default base:** `origin/master`. If the default branch is **`main`**, use **`origin/main`** or **`origin/HEAD`** (whichever matches this repo).
- **Dirty worktree:** Do not switch automatically if work would be lost — ask.
- **Sync remote refs:** `git fetch origin` (updates `origin/master`, etc., without merging into your current branch — safe when you are mid-work elsewhere).
- **Base must be current before branching — pick one pattern:**
  - **A (recommended):** After `fetch`, create the feature branch **from the remote tip**: `git checkout -b {KEY}/{slug} origin/master` (or `origin/main`). No need for a separate `git pull` on `master`; the new branch starts at the same commit as the remote default branch.
  - **B:** If you check out a **local** `master`/`main` first, **fast-forward it** before branching: `git checkout master && git pull origin master` (or `git merge origin/master`), then `git checkout -b {KEY}/{slug}`. Otherwise the local base may lag behind `origin`.
- **`fetch` vs `pull`:** `pull` = `fetch` + merge/rebase into the **current** branch. We call **`fetch` explicitly** so the agent always refreshes remote refs; then either branch from **`origin/<base>`** (pattern A) or **`pull`** on the local base (pattern B). Both achieve an up-to-date starting point for `{KEY}/{slug}`.

### 4. Artifacts

- After **`{KEY}/{slug}`** is the current branch, create **`.cursor/temp/{KEY}/{slug}/`** if missing (mirror rule in **`people_domain.mdc`**).

## Commit messages

Use **English**, imperative mood, and the format in the **always-applied Cursor rules** for this repository.

## Decision sketch

- **Issue missing?** → Create/propose (§1) → then branch.
- **Issue exists, branch wrong/missing?** → Align key (most specific, per reference) → base branch → new `{KEY}/{slug}`.
- **Already on correct `{KEY}/…`?** → Sync base if needed; skip redundant branch creation.
