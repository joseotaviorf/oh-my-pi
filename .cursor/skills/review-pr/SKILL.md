---
name: review-pr
description: Run a full pre-push code review against all CI checks in parallel. Catches style, DAG declaration, metadata, and Python convention issues before they fail in Woodpecker. Use when the user asks to review changes, prepare a PR, check if code is ready to push, validate a DAG, or check a DAG before pushing.
---

# Pre-Push PR Review

## When to use

Before opening a PR, or when asked to verify that staged/changed files will pass CI. The 10-step Woodpecker pipeline is the ground truth — this skill replicates its key checks locally in parallel.

## Step 1 — Get the changed files

Run `git diff --name-only origin/master...HEAD` (or against `HEAD` if not yet committed) to get the exact list of changed files. Categorize them:

- `.py` files → Python convention check
- `*_declaration.yml` → DAG declaration validation
- `queries/**/*.sql` → SQL + metadata pair check
- `metadata/**/*.yml` → Metadata content check
- `bietlejuice/**/*.py` → Style check

## Step 2 — Launch subagents in parallel

Use the Task tool for all six subagents below simultaneously.

**Subagent A — Style check (shell):**
```bash
make check-style && make check-style-dags
```
Return: exit code, any Ruff error lines or `would reformat`.

**Subagent B — DAG declaration validation (shell):**

For each changed `*_declaration.yml`, extract the `dag_name` from the folder name and run:
```bash
make validate-dag-declaration-files dag_name={dag_name}
```
Return: exit code and any error lines per DAG.

**Subagent C — SQL/metadata pair check (explore):**

For every changed `.sql` file, verify that a matching `.yml` exists in `metadata/{layer}/` with the same base name. Also check:
- `description:` field is present and ≥ 10 chars
- All columns have `lineage:` (enrich/dw) or `dimension:`/`metric:` block (metric layer)
- **Python `str.format` on query files:** For `dags/**/queries/**/*.sql` loaded by `query_delta`-style pipelines (`TableLoaderPipeline` applies `.format(**query_template_params)`), scan for `{` inside string literals. Regex quantifiers (e.g. `{4}`, `{2,3}`), JSON, or other literals must use **`{{` / `}}`** so Spark receives single braces; otherwise the job fails at runtime with `KeyError` or `IndexError` (see **`databricks_conventions.mdc`** — Literal Braces, and **`sql_conventions.mdc`** §13). Flag obvious mistakes as **blocking** when the pattern is clearly a literal brace, not a declared `{load_start_date}`-style key.

Return: list of missing or incomplete metadata files.

**Subagent D — Python convention check (explore):**

For every changed `.py` file in `bietlejuice/`, verify:
- Uses `QuintoAndarLogger`, not `logging.getLogger`
- No wildcard imports (`from x import *`)
- No bare `raise NotImplementedError()` (use `@abstractmethod` instead)
- Pydantic: `model_dump()` not `.dict()`, `field_validator` not `validator`
- **No new `SparkSession` or `SparkContext` creation** — look for `SparkSession.builder...build()`, `SparkSession(...)`, `SparkContext(...)`, or `SparkContext(conf=...)`. The only acceptable pattern is `SparkSession.builder.getOrCreate()`. Creating a second session causes intermittent library-resolution failures on shared clusters (incident ref: PR #22756).

Return: file path + line number for each violation found.

**Subagent E — Test coverage check (explore):**

For every new `.py` file under `packages/*/src/bietlejuice/` (not an `__init__.py`), check whether a companion test exists under that package’s `test/unit/` mirroring the source path (see `testing_conventions.mdc`). Spark jobs under `dags/**/spark_jobs/` → `packages/bietlejuice-runtime/test/dags/…`; core model jobs → `packages/bietlejuice-runtime/test/core_model_dags/…`.

Return: list of new source files with no matching test file. Classify as **non-blocking** if the file is a config/constants module; **blocking** if it contains a class or function with business logic.

**Subagent F — Lint check (shell):**
```bash
make lint
```
Return: exit code, all warning/error lines. Classify as **blocking** if exit code is non-zero.

**Subagent H — Source layer policy check (shell):**
```bash
make validate-source-layer-policy CI_COMMIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```
- Exit code `1` → **blocking** (new files violate layer policy or core model coverage)
- Exit code `0` with violation output → **non-blocking but should fix** (warnings on existing files)
- Exit code `0` with no output → clean

Return: exit code, full output. Note: this check only runs when the branch touches files under `dags/`; if no DAG files are changed, the script exits 0 with a skip message.

## Step 2b — PR scope check (manual, no subagent)

After gathering the changed files list from Step 1, assess whether the PR is **tightly scoped**:

1. Identify the PR's primary intent (e.g., "add column mapping to delta loader", "create new DW table").
2. Flag any changed files that do **not** directly serve that intent — especially modifications to shared base classes, loaders, Spark session setup, or utility modules that are unrelated to the feature.
3. If a base class or shared loader (`bietlejuice/base/`, `bietlejuice/services/`, or any module imported by multiple DAGs) is modified, flag it as **high-impact** and recommend:
   - Confirming the change is essential to the feature (not a drive-by refactor).
   - Triggering at least 2–3 DAGs that use the same loader/base class after merge to validate there are no intermittent regressions.

Classify scope issues as **non-blocking but should fix** — PRs with unrelated changes to shared infrastructure are a known source of intermittent production incidents (ref: PR #22756).

4. **PR topic cohesion check**: Analyze the changed files and commit messages to identify how many **distinct themes** the PR addresses (e.g., new feature, refactor, bug fix, config change, dependency update).
   - A PR should ideally address **one theme**.
   - If it mixes two or more unrelated themes, suggest splitting into separate PRs — one per theme.
   - Propose a concrete split when possible (e.g., "refactor of the loader in one PR, new column mapping feature in another").
   - A small PR that mixes unrelated changes is worse than a large focused one, but even single-theme PRs with many files benefit from splitting into incremental batches to make review manageable.

## Step 3 — Synthesize findings

Group all issues by severity:

**Blocking (will fail CI):**
- Style errors (black/flake8)
- Lint errors (`make lint`)
- Missing metadata files
- DAG declaration schema errors
- `personal_data_classification` present in metadata YAML (field not supported by CI yet — remove it)

**Non-blocking but should fix:**
- Python convention violations
- Incomplete metadata (short descriptions, missing lineage)
- New `bietlejuice/` module with no matching unit test file (config/constants modules exempt)
- PR includes unrelated changes to shared base classes or loaders (scope creep)
- New `SparkSession` or `SparkContext` creation instead of `getOrCreate()`
- PR mixes multiple unrelated themes — suggest splitting into one PR per theme
- Source layer policy warning in **existing** files (exit code 0 with output from Subagent H)

For each issue: file path, line (if available), what is wrong, exact fix.

## Step 4 — Generate PR description draft

If all checks pass (or after fixes are applied), draft the PR description using this template:

```markdown
### Why?
[Brief explanation of the motivation for this change]

### What?
[What was changed — list the DAGs, tables, or modules modified]
- [Change 1]
- [Change 2]

### How everything was tested?
[Describe how the change was validated]
- make validate-dag-declaration-files dag_name={dag_name} ✅
- make validate-metadata-files-content ✅
- make check-style ✅
- make check-style-dags ✅
- make lint ✅
- [Screenshot of DAG run if applicable]

### !Attention Points!
[Any reviewers need to be aware of — schema changes, downstream impact, etc.]

### Checklist before opening the PR!
- [ ] Code follows style guidelines and name conventions
- [ ] Corresponding metadata/documentation changes made
- [ ] Tests added or updated
```

## Step 5 — Final check

If any blocking issues were found, do NOT generate the PR description yet. Fix the issues first (or guide the user to fix them), then re-run only the failing subagents to confirm.
