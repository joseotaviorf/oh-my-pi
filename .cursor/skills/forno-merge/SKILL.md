---
name: forno-merge
description: Merge current branch into forno and push; on conflict resolve with user, then verify and push. Use when syncing with forno or "merge to forno".
---

# Forno merge

Merge the current branch into `forno` and push. **On conflict**, follow the conflict-resolution workflow below (do not auto-choose "branch version vs forno version" by file list alone).

---

## Step 1 — Git changes validation

**1.1 — Branch check**

- Current directory is the repo root (or pass repo path).
- If the current branch is `master` or `forno`, **stop and report an error** to the user: this skill merges a feature branch *into* forno; you cannot run it from master or forno. Ask the user to checkout a feature branch (or provide the branch name to use) and try again.
- Otherwise, current branch is the one to merge into forno (e.g. feature branch). Note the branch name for use in later steps.
- **Branch operations scope:** Only `git checkout` (existing branches) and `git merge` are allowed. Never create or delete branches without explicit user instruction.

**1.2 — Working tree check**

Run `git status --porcelain`.

- If the output is **empty** (no pending changes) → proceed directly to **Step 2**.
- If there are **pending changes** (uncommitted, unstaged, or untracked files) → list the changed files and ask the user how to proceed using AskQuestion with two options:
  - **Option A — Commit changes**: add and commit the pending changes (ask the user for a commit message).
  - **Option B — Keep untracked**: leave the changes as-is and proceed without committing.
- Apply the user's decision before advancing to Step 2.

---

## Step 2 — Pre-merge validation

**Without asking the user anything yet**, run the following automatically:

**2.1 — Detect changed file categories**

```bash
git branch --show-current
git diff --name-only origin/master...HEAD -- '*.py'
git diff --diff-filter=A --name-only origin/master...HEAD -- '*_declaration.yml'
```

If neither query returns results, skip checks entirely (nothing to run) and proceed to **Step 3**.

**2.2 — Run checks**

If `*.py` changed: run `make check-style` and `make unit-tests` in parallel.
If new `*_declaration.yml` detected: run `make validate-dag-declaration-files dag_name={dag_name}` for each newly added DAG (can run in parallel with the above).

**2.3 — Evaluate results and proceed**

- **All checks passed** (or no checks were needed): log the result briefly ("Checks: all passed" or "No checks needed") and proceed directly to **Step 3** without asking.
- **Any check failed**: report the failures to the user and ask how to proceed:
  - **fix** — apply the user's fix, then re-run the failed check.
  - **proceed anyway** — advance to Step 3 despite the failure (only with explicit user approval).
  - **switch branch** — `git checkout <branch indicated by user>` and restart from Step 1.
- **After all fixes are applied**: run `make lint` to auto-format. If `make lint` changed files, inform the user which files were formatted.

Do **not** advance to Step 3 with check failures without explicit user approval.

---

## Step 3 — Fetch and start merge

Run:

```bash
git fetch origin
git checkout forno
git pull origin forno
git merge <current_branch> -m "Merge <current_branch> into forno"
```

Use the actual current branch name (e.g. `git branch --show-current`) in place of `<current_branch>`.

- If the merge **succeeds** (no conflict), go to **Step 5**.
- If the merge **fails** due to conflict, go to **Step 4**.

---

## Step 4 — Resolve conflicts

When `git merge` reports conflicts, **do not** resolve or apply any change without first consulting the user. Follow this workflow:

1. **Identify** conflicting files via `git diff --name-only --diff-filter=U`. Report the list to the user.

2. **Classify** each conflicting file: compute the merge base (`git merge-base <origin_branch> MERGE_HEAD`) and list files changed in the feature branch since that point (`git diff $BASE...MERGE_HEAD --name-only`). For each conflict, report whether the feature branch touched it. Suggest keeping forno's version for files **not** touched by the feature branch.

3. **Explain and ask:** For each conflicting file changed by the feature branch, explain what each side changed and ask the user how to resolve (keep forno, keep branch, combine, or other). Do not apply any resolution until the user has given direction.

4. **Apply and commit:** Edit files per the user's guidance, remove conflict markers, then run:
   ```bash
   git add <resolved_files>
   git commit -m "Merge <current_branch> into forno"
   ```

Then proceed to **Step 5**.

---

## Step 5 — Dependencies and push

On branch `forno` (merge already committed, with or without having had conflicts).

**5.1 — Update dependencies**

```bash
make dependencies-file
```

If the working tree changed (e.g. `dags/dependencies.yaml` updated), run:

```bash
git add dags/dependencies.yaml
git commit --amend --no-edit
```

**5.2 — Push and return to feature branch**

```bash
git push origin forno
```

If the push is **rejected** (e.g. someone else pushed to `forno` in the meantime), run `git pull origin forno`, resolve any new conflicts if present, then try `git push origin forno` again.

**After the push succeeds (or after all retries)**, always return to the feature branch:

```bash
git checkout <original_branch>
git branch --show-current
```

Verify the output of `git branch --show-current` matches `<original_branch>`. If the checkout fails for any reason, report the error to the user with manual instructions: `git checkout <original_branch>`.

Report success: "Merge to forno complete. Push confirmed. You are back on `<original_branch>`."
