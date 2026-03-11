---
name: forno-merge
description: Merge current branch into forno and push; on conflict resolve with user, then verify and push. Use when syncing with forno or "merge to forno".
---

# Forno merge

Merge the current branch into `forno` and push. **On conflict**, follow the conflict-resolution workflow below (do not auto-choose "branch version vs forno version" by file list alone).

---

## Step 1 — Preconditions

- Current directory is the repo root (or pass repo path).
- **Branch check:** If the current branch is `master` or `forno`, **stop and report an error** to the user: this skill merges a feature branch *into* forno; you cannot run it from master or forno. Ask the user to checkout a feature branch (or provide the branch name to use) and try again.
- Otherwise, current branch is the one to merge into forno (e.g. feature branch). Note the branch name for use in Step 2.
- **Branch operations scope:** The only branch operations authorised in this skill are `git checkout` (to existing branches) and `git merge`. **Never** create (`git checkout -b`, `git branch <name>`) or delete (`git branch -d`, `git branch -D`, `git push origin --delete`) any branch. If the workflow would require creating or deleting a branch, stop and ask the user for explicit instruction.

---

## Step 2 — Pre-merge validation

**Without asking the user anything yet**, run the following automatically:

**2.1 — Collect context and run relevant checks in parallel**

```bash
git branch --show-current
git diff --name-only origin/master...HEAD
```

Based on the changed files, **immediately** launch the relevant checks as parallel subagents (Task tool, `subagent_type: shell`):

| If any file matches | Run |
|---------------------|-----|
| `bietlejuice/**/*.py` or any `.py` | `make unit-tests`, `make lint`, `make check-style` (three parallel subagents) |
| `**/*_declaration.yml` | `make validate-dag-declaration-files dag_name={dag_name}` for each changed DAG |

If no file matches either category, skip checks (nothing to run).

**2.2 — After all checks finish, present a single report to the user**

Run `git status --porcelain` and compose **one message** with everything:

> "Branch: `<branch_name>` → forno.
> Checks: [all passed / X failed — details below].
> Working tree: [clean / X uncommitted file(s): list].
> How do you want to proceed?
> - **yes / proceed** — go ahead with the merge
> - **switch branch** — tell me which branch to use instead
> - **[instruction]** — to handle any pending item (fix a failure, commit, stash, etc.)"

**2.3 — Handle the user's response**

- **"yes" / "proceed"**: if working tree is clean → go to Step 3. If there are uncommitted changes → apply the user's instruction (commit with a message they provide, or `git stash`) and then go to Step 3.
- **"switch branch"**: `git checkout <branch indicated by user>` and restart from Step 1.
- **Any other instruction** (fix failure, commit, stash, etc.): apply it, then ask if they want to proceed with the merge.

Do **not** advance to Step 3 with uncommitted changes or check failures without explicit user approval.

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

When `git merge` reports conflicts, **do not** resolve or apply any change without first consulting the user. The user must give the orientation on how to handle each conflict. Follow this workflow:

1. **Identify** the conflicting files and the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
   Command: `git diff --name-only --diff-filter=U` (or `git status`). Report the list to the user.

2. **Classify by feature-branch changes:** Compare the feature branch to the **origin branch in the version from which the feature branch was created** (merge base), so only files actually changed in the feature branch are considered.
   - Choose the origin branch (e.g. `origin/master` or `origin/forno`) from which the feature branch was created.
   - Merge base (point where the feature branch was generated from the origin): `BASE=$(git merge-base <origin_branch> MERGE_HEAD)`.
   - List files changed in the feature branch since that point: `git diff $BASE...MERGE_HEAD --name-only` (run while on `forno` with merge in progress; `MERGE_HEAD` is the tip of the branch being merged).
   - For each conflicting file, report whether it appears in that list or not.
   - **Suggest:** Conflicting files that were **not** changed in the feature branch (relative to that base) should remain as in forno (keep forno's version; they likely changed only on forno). For conflicting files that **were** changed in the feature branch, ask the user how they want to resolve (keep forno, keep branch, or combine). Present this classification and suggestion to the user.

3. **Explain** what each side changed and why the conflict arose (forno vs the user's branch). Present this to the user.

4. **Pause and ask:** Ask the user how they want to resolve each conflict (e.g. keep forno, keep branch, combine both, or other). Do **not** suggest or apply a resolution until the user has given direction. For files not changed in the feature branch, you may recommend keeping forno; the final decision is still the user's.

5. **Apply** only after the user has instructed: edit the conflicting files according to the user's guidance, remove conflict markers, then:
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

If the working tree changed (e.g. `dependencies.yaml` updated), run:

```bash
git add -A
git commit --amend --no-edit
```

**5.2 — Push and return to your branch**

```bash
git push origin forno
git checkout <original_branch>
```

If the push is **rejected** (e.g. someone else pushed to `forno` in the meantime), run `git pull origin forno`, resolve any new conflicts if present, then try `git push origin forno` again before checking out the original branch.

Confirm the user is back on their feature branch.

---

## Step 6 — Confirm

- Pre-merge checks (unit-tests, lint, check-style, DAG declaration) were run in Step 2 against the changed files before the merge; any failures were resolved with user input before proceeding.
- Forno branch is updated on `origin` (if push was rejected, pull was done and push retried until success).
- User is back on their original branch.
- `make dependencies-file` was run post-merge; if it produced changes, they were amended into the merge commit before pushing.
- If there were conflicts, the resolution followed the identify → classify → explain → ask → apply workflow.
