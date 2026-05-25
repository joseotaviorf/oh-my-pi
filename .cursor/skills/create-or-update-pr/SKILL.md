---
name: create-or-update-pr
description: Generate a standardized Pull Request title and description based on current changes, and create or update the PR using GitHub CLI. Use when the user asks to open a PR, update PR info, or generate a PR description.
---

# Create or Update Pull Request

## When to use

- When opening a new PR
- When updating PR title/description
- When asked to generate a PR description
- After code review is complete

**Related:** For local checks before opening a PR (style, DAG YAML, SQL/metadata), use the **`review-pr`** skill. This skill focuses on **title/body generation** and **`gh` automation**.

---

## Execution order (checklist)

Run steps **in this order** (agents should not skip):

1. Diff + commits → title + description (Steps 1–5, including **5.3–5.4** merge when editing an existing PR)
2. `gh` installed + authenticated (Step 6); use `env -u GITHUB_TOKEN` when API returns 401 (see 6.4)
3. Resolve `ASSIGNEE` (Step 7)
4. **Commit** any intended changes; then **push** branch to `origin` (Step 8)
5. Detect existing PR (Step 9)
6. `gh pr create` or `gh pr edit` with **`--body-file`** and assignee (Step 10)
7. Print title, body, URL, assignee status (Step 11)

---

## Step 1 — Get changed files

Ensure the default branch ref exists (one of):

```bash
git fetch origin master 2>/dev/null || git fetch origin main 2>/dev/null || true
```

Then list files changed against the remote default branch (prefer **merge base** of the current branch):

```bash
git diff --name-only origin/master...HEAD 2>/dev/null || git diff --name-only origin/main...HEAD 2>/dev/null
```

If still empty (e.g. no upstream yet or only unstaged work):

```bash
git diff --name-only HEAD
git status --porcelain
```

Identify:

- New files (A)
- Modified files (M)

**Uncommitted changes:** If `git status` shows modified files that **should** be in the PR, stop and ask the user to **commit** (or explicitly scope the PR to what is already committed). Do not silently ignore uncommitted work.

---

## Step 2 — Infer PR type (Conventional Commits prefix)

Rules:

- New feature (new DAG, SQL, module) → **feat**
- Bug fix → **fix**
- Refactor (no behavior change) → **refactor**
- Infra/config → **chore**
- Docs only → **docs**

**Fallback:** `feat`

---

## Step 3 — Infer scope (optional)

If the branch name or commits include a **Jira key**, use it as **scope** in **lowercase** (e.g. `aarede-372`) — see **`.cursor/rules/pr_template.mdc`**. Otherwise, from changed paths pick a short scope (snake_case), in priority order:

1. DAG folder name when `dags/**/<dag_name>/` or `*_declaration.yml` is touched
2. Base name of a primary `.sql` under `queries/`
3. `bietlejuice/` submodule area if only library code changed

**Fallback:** omit scope or use `data_pipeline`

---

## Step 4 — Generate title

Preferred format (Conventional Commits):

```text
<type>(<scope>): <short imperative description>
```

Examples:

- `feat(jira_ops): ingest schedules and user accounts from Jira Ops API`
- `fix(payments_join): correct null handling in join keys`

When a **Jira key** exists (e.g. `ABC-123` from branch/commits), put it in **scope** in **lowercase** (`abc-123`) — **not** a suffix at the end of the title:

- `feat(abc-123): ebdb_agent prospect tables and qualification layer`
- `feat(aarede-372): add prospect and qualification tables to ebdb_agent clean layer`

If the user wants the older short form:

```text
<type>: <imperative description>
```

Keep the title **under ~72 characters** when possible. Titles must be **English** (same as the PR body; see **`.cursor/rules/pr_template.mdc`**).

---

## Step 5 — Generate description

### 5.1 — Content rules (canonical: Cursor rule)

- **Structure and editorial rules:** Follow **`.cursor/rules/pr_template.mdc`** — read that file and use its **Guidelines** (English mandatory, title `feat(abc-123): …` when a key exists, **Why?** with a **second bullet** `Jira: [KEY](url)` when applicable) and its **section skeleton** (`### Why?` with two bullets max for ticket context; no `##` Jira heading; then `### What?`, `### How everything was tested?`, etc.). Do not duplicate a second template inside the skill; the rule is the source of truth for the generated PR body.
- **Language:** PR **title** and **body** must be **English**, per the rule — even if the user writes in another language in chat. The assistant’s reply to the user may stay in the user’s language; the generated PR text does not.
- Base **Why?** / **What?** on the **actual diff and commits** (`git log --oneline origin/master..HEAD` or `origin/main..HEAD`). **Do not invent** files, tickets, or behavior not present in the repo.
- **Checklist:** Per **`.cursor/rules/pr_template.mdc`** guideline **11**, **new** PR bodies must end with **`### Checklist before opening the PR!`** copied from **`.github/PULL_REQUEST_TEMPLATE.md`**. When **updating** a PR, **never drop** an existing checklist — preserve it verbatim (rule **10**). If the old body had **no** checklist, **append** the default checklist once so the description matches the GitHub template.

### 5.2 — Filling the body

1. Open **`.cursor/rules/pr_template.mdc`** and build **`/tmp/pr_body.md`** (or the body file used in Step 10) from its structure: **Why?** = first bullet purpose, second bullet `Jira: [link]` only if a ticket exists; then **What?** and the rest.
2. Apply the numbered **Guidelines** at the top of the rule (**English** for all PR prose; omit empty sections; no filler “N/A” outside **Screenshots**; remove bracketed instructional hints from the final text except the rule’s **Screenshots** placeholder).
3. For commands/tests relevant to this repo (when applicable), examples include `make check-style`, `make check-style-dags` (CI runs both on every push/PR), `make validate-dag-declaration-files dag_name=<name>` — only list what was run or what CI will run.

### 5.3 — Screenshots subsection

Follow **`.cursor/rules/pr_template.mdc`** guideline **9** (always include `#### Screenshots`).

- **New PR or no prior body:** Append the **canonical placeholder** bullet from the rule skeleton (English; tells the author to add visuals or replace with `Not applicable` / remove the line).
- **Updating an existing PR:** Before overwriting the body, fetch the current description, e.g. `ghq pr view --json body -q .body` (or read from the GitHub API response used in Step 10.1). If the markdown contains `#### Screenshots` and the content **below that heading** is **not** empty and **not** only the canonical placeholder (e.g. it has image links, `![…]`, or substantive bullets), **copy that entire `#### Screenshots` block verbatim** into the new `/tmp/pr_body.md`. Otherwise keep the canonical placeholder.

This preserves author-added screenshots while still leaving a visible to-do when nothing was filled in yet.

### 5.4 — Preserve all other sections (no disappearing topics)

Follow **`.cursor/rules/pr_template.mdc`** guidelines **7**, **10**, and **11**.

When **creating** a PR, the file in Step 10 must include the full skeleton from the rule: through **`### Checklist before opening the PR!`** (from **`.github/PULL_REQUEST_TEMPLATE.md`**) unless the user explicitly asks to omit it.

When **updating** a PR:

1. Fetch **`BODY_OLD`** with `ghq pr view --json body -q .body` (strip trailing GitHub/Jira auto-footnotes only if you are re-adding a clean Jira link under **Why?**; otherwise leave footnotes alone).
2. Build **`BODY_CORE`**: regenerated **`### Why?`**, **`### What?`**, **`### How everything was tested?`**, and **`#### Screenshots`** (per **5.3**).
3. From **`BODY_OLD`**, extract and **append verbatim in original order** every block that must not be regenerated:
   - **`### !Attention Points!`** through the line before the next top-level `###` (if present).
   - **`### Checklist before opening the PR!`** through **end of file** (if present) — keep every `- [x]` / `- [ ]`.
   - Any **other** `### …` heading that is not `Why?`, `What?`, or `How everything was tested?` (team-specific notes), same rule: preserve the full block in order.
4. Final body = **`BODY_CORE`** + preserved blocks (typical order: **Attention** → **Checklist**; match **`BODY_OLD`** order when in doubt).
5. If **`BODY_OLD`** had **no** checklist, **append** the default checklist from **`.github/PULL_REQUEST_TEMPLATE.md`** after the preserved blocks (guideline **11**).

**Never** drop **`### Checklist before opening the PR!`** or other existing `###` sections when refreshing a description.

---

## Step 6 — Ensure GitHub CLI is available and authenticated

Define a shell helper for the session (avoids repeating `env -u`):

```bash
ghq() { env -u GITHUB_TOKEN -u GH_TOKEN gh "$@"; }
```

Use `ghq` (or inline `env -u GITHUB_TOKEN -u GH_TOKEN gh ...`) for **all** `gh` calls if the environment often sets broken tokens. **`gh` may read `GITHUB_TOKEN` or `GH_TOKEN`**; clear both when debugging 401s.

### 6.1 — Check if GitHub CLI is installed

```bash
gh --version
```

If the command is not found:

- **macOS (Homebrew):** `brew install gh`
- **Linux (apt):** `sudo apt install gh` (or follow [docs](https://cli.github.com/manual/installation))

If installation is not possible in the environment, tell the user to install manually and **stop** before `gh pr create/edit`.

---

### 6.2 — Check authentication status

```bash
ghq auth status
```

(use plain `gh` only if you are sure no bad token is exported)

---

### 6.3 — If not authenticated

```bash
gh auth login
```

---

### 6.4 — Token env var conflicts (common 401 / “invalid token”)

Many shells export **`GITHUB_TOKEN`** or **`GH_TOKEN`** (CI, old PAT). If either is **invalid**, **`gh` uses it first** and API calls return **401** even when `gh auth login` works via **keyring**.

**Fix:** run `gh` without those variables (see `ghq()` above), or `unset GITHUB_TOKEN GH_TOKEN` for the session.

---

### 6.5 — Confirm authentication

Run `ghq auth status` until healthy. Do not create or edit the PR until API calls succeed.

---

## Step 7 — Resolve assignee (default: current user)

**Assignee was missing when `gh pr create` ran without `--assignee`.** By default, assign the authenticated user:

```bash
ASSIGNEE=$(ghq api user --jq .login)
```

If this fails, omit `--assignee` / `--add-assignee` and say so in the output.

---

## Step 8 — Commit (if needed) and push the branch to `origin`

**Push is required** before `gh pr create` for a new remote branch. Errors you may see without push:

- `Head sha can't be blank`, `Base sha can't be blank`
- `No commits between master and <branch>`
- `Head ref must be a branch`

**Check remote tracking:**

```bash
git branch -vv
git ls-remote --heads origin "$(git branch --show-current)"
```

**Push:**

```bash
git push -u origin "$(git branch --show-current)"
```

If push fails (no permission), **stop** and tell the user to push manually.

---

## Step 9 — Check whether a PR already exists for this branch

```bash
ghq pr view --json number,url,assignees --jq .
```

- If JSON includes `number` → PR exists (note `url`; check `assignees` if you need to add one).
- If the command exits non-zero (e.g. "no pull requests found") → no PR for this branch.

Alternative:

```bash
ghq pr list --head "$(git branch --show-current)" --json number,url --jq .
```

---

## Step 10 — Create or update the PR (`--body-file` + assignee)

**Never** pass multiline `--body "..."`; **always** write the body to a file and use **`--body-file`**.

Write the file to a temp path, e.g. `/tmp/pr_body.md` (Unix) or `%TEMP%\pr_body.md` (Windows). Do not commit secrets inside it.

### Create (no PR yet)

```bash
ghq pr create \
  --title "GENERATED_TITLE" \
  --body-file /tmp/pr_body.md \
  --assignee "${ASSIGNEE}" \
  --draft
```

Omit `--draft` if the user wants **Ready for review** immediately.

### Update (PR already exists)

```bash
ghq pr edit \
  --title "GENERATED_TITLE" \
  --body-file /tmp/pr_body.md
```

Then **ensure assignee**:

```bash
ghq pr edit --add-assignee "${ASSIGNEE}"
```

If `--add-assignee` errors (e.g. already assigned), treat as success. If it fails for permissions, report and continue.

### 10.1 — Fallback when `gh pr edit` / `gh pr create` fails (GraphQL / Projects classic)

Some repos return **exit code 1** with a message like:

`GraphQL: Projects (classic) is being deprecated ... (repository.pullRequest.projectCards)`

In that case the PR may **not** be updated even though `gh` prints the warning. Use the **REST API** instead (same auth as `gh`):

**Update title and body:**

```bash
ghq api -X PATCH "repos/{owner}/{repo}/pulls/{PR_NUMBER}" \
  -f title="GENERATED_TITLE" \
  -F body=@/tmp/pr_body.md
```

(`owner` / `repo` / `PR_NUMBER` from `gh repo view --json nameWithOwner -q .nameWithOwner` and `ghq pr view --json number -q .number`.)

**Set assignee** when `gh pr edit --add-assignee` does not stick:

```bash
echo "{\"assignees\":[\"${ASSIGNEE}\"]}" | ghq api -X POST "repos/{owner}/{repo}/issues/{PR_NUMBER}/assignees" --input -
```

Use the **issue** number for the PR (same as PR number).

---

## Step 11 — Output (always give the user the PR link)

After **create** or **edit**, resolve the canonical browser URL and **show it clearly** — users often miss it in CLI noise.

1. Fetch URL and number (works after both `pr create` and `pr edit`):

   ```bash
   ghq pr view --json number,url,title --jq '{number, url, title}'
   ```

2. **Required user-facing block** (put this near the **top** of the assistant’s final message so it is impossible to miss):

   - A **clickable markdown link**: `[PR #<number>](<url>)` or plain `https://github.com/...`
   - One line: **Created** | **Updated** | **Failed**
   - If **Failed**: paste `gh` stderr and, if applicable, the “open a PR” hint URL from `git push` output

3. Then include (as today):

   - **Title** (code block)
   - **Description** (full body)
   - **Assignee(s)** or “not set” / skipped reason

**Note:** `gh pr create` prints a URL on success — still run `ghq pr view --json url` so the agent always returns the same structured link even when output was truncated.

---

## Behavior rules

- **English** for PR title and body (see **`.cursor/rules/pr_template.mdc`**); chat with the user may use their locale.
- Keep the title short and specific.
- **Never invent** tickets, file paths, or test results not supported by the diff or user message.
- Prefer clarity over cleverness.
- If multiple areas are touched, prefer one primary scope or split into a short **What?** list.
- Do not run `gh pr create` if `gh` is unavailable or not authenticated.
- Prefer **body-file** over inline `--body` for any description longer than one line.
- **Commit → push → create/edit**; **assign** the current user by default; use **`ghq`** / `env -u GITHUB_TOKEN -u GH_TOKEN` when tokens break API calls.
- **Always surface the PR URL** to the user in the final reply (markdown link + PR number). This is part of a successful skill run, not optional metadata.
- **Screenshots:** Never drop the `#### Screenshots` heading from generated bodies; merge existing PR content per Step **5.3**.
- **Sections:** Never drop existing **`### …`** topics when updating a PR (checklist, Attention Points, custom headings); merge per Step **5.4**. New PRs include the default checklist per the rule.
