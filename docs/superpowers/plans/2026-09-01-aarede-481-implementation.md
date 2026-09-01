# AAREDE-481 Strict Primary Market House Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the enriched house table classify Primary Market listings from the `sale_type` source-of-truth enum.

**Architecture:** Keep the existing `datalake_ebdb_listing.house` output schema and one-row-per-house grain. Change only the `listing_info` aggregation to test `sale_type = 'PRIMARY'`; retain the already EMR-safe `_t` subquery and `WHERE _w = 1` context selection.

**Tech Stack:** Spark SQL consumed by Databricks DBR 16.4 and EMR Spark 3.5, YAML governance metadata, repository `make` validators, Trino production evidence.

## Global Constraints

- Modify only `dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql` and its paired `metadata/enrich/house.yaml` for functional behavior
- `sale_type = 'PRIMARY'` is `TRUE`; `NULL` and every other value are `FALSE`
- Never use legacy `is_primary_market` as a fallback
- Preserve `is_sale_primary_market`, house grain, and existing final `COALESCE(..., FALSE)`
- Keep SQL compatible with Databricks DBR 16.4 and plain EMR Spark 3.5
- Do not modify DW, downstream facts, production data, TARS artifacts, or ingestion declarations
- Run EMR SQL lint immediately after the SQL edit
- Use static validation only; do not claim Forno validation
- Deliver from `AAREDE-481/derive-house-primary-market` as a draft PR

---

## File Map

| File | Responsibility | Change |
|---|---|---|
| `dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql` | Builds the enriched house row and derives listing flags | Replace the legacy primary-market boolean aggregation |
| `dags/house_and_listing/enrich_ebdb_listing/metadata/enrich/house.yaml` | Documents the enriched house schema and column lineage | Point `is_sale_primary_market` lineage and description at `sale_type` |

The current master baseline already contains the EMR migration wrapper:
`ROW_NUMBER() OVER (PARTITION BY h.id ...) AS _w` inside `_t`, followed by
`WHERE _w = 1`. Do not add a second ranking CTE or alter that selection.

## Task 1: Implement strict enum derivation and metadata

**Files:**

- Modify: `dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql:33-51`
- Modify: `dags/house_and_listing/enrich_ebdb_listing/metadata/enrich/house.yaml:597-601`
- Test: no new fixture by approved Phase 0 decision; repository validators are the test gate

**Interfaces:**

- Consumes: `datalake_ebdb_clean.listing_sale_model.sale_type`
- Produces: existing `datalake_ebdb_listing.house.is_sale_primary_market`
- Preserves: existing house row grain, column name, and null coalescing behavior

- [ ] **Step 1: Confirm the branch and clean implementation baseline**

Run:

```bash
git branch --show-current
git status --short
git diff -- dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql \
  dags/house_and_listing/enrich_ebdb_listing/metadata/enrich/house.yaml
```

Expected: branch is `AAREDE-481/derive-house-primary-market`; no unstaged
functional changes exist; the current SQL contains the legacy aggregation and
the current metadata points to `is_primary_market`.

- [ ] **Step 2: Replace the legacy aggregation**

In `listing_info`, replace exactly:

```sql
    BOOL_OR(lsm.is_primary_market) AS is_sale_primary_market,
```

with:

```sql
    BOOL_OR(lsm.sale_type = 'PRIMARY') AS is_sale_primary_market,
```

Do not change the joins, grouping, output alias, or `_t`/`_w` wrapper.

- [ ] **Step 3: Run EMR SQL lint immediately after the SQL edit**

Run critical-pattern checks against the edited file:

```bash
if rg -n -i \
  -e '\bQUALIFY\b' \
  -e '\bGROUP BY ALL\b' \
  -e '\bIFF\s*\(' \
  -e '\bDECODE\s*\(' \
  -e '\bDATEDIFF\s*\(\s*(YEAR|QUARTER|MONTH|WEEK|DAY|HOUR|MINUTE|SECOND|MILLISECOND|MICROSECOND)\b' \
  -e '[A-Za-z_][A-Za-z0-9_]*:[A-Za-z_]' \
  -e '/\*\+[^*]*\b(RANGE_JOIN|SKEW)\b' \
  dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql
then
  echo "EMR lint finding"
  exit 1
else
  test $? -eq 1
fi
```

Run join-shape validation:

```bash
uv run --project packages/bietlejuice-compiler python \
  packages/bietlejuice-compiler/scripts/ci_cd/validate_join_shapes.py \
  --paths dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql \
  --json
```

Expected: the critical-pattern command prints no matches and the join-shape
JSON has an empty `violations` array. Any finding must be resolved before
continuing.

- [ ] **Step 4: Update the paired metadata**

Replace the current metadata block:

```yaml
  is_sale_primary_market:
    lineage:
      - datalake_ebdb_clean.listing_sale_model.is_primary_market
    description: Whether the sale listing is primary market (new development sold by the
      builder).
```

with:

```yaml
  is_sale_primary_market:
    lineage:
      - datalake_ebdb_clean.listing_sale_model.sale_type
    description: Whether any sale listing for the house has sale_type PRIMARY, identifying a
      new development sold by the builder. NULL and non-PRIMARY values are false; the legacy
      is_primary_market flag is not used as a fallback.
```

- [ ] **Step 5: Validate the SQL and metadata pair**

Run:

```bash
make validate-metadata-files-content
make validate-lineage-consistency
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-fair-metadata
```

Expected: all commands exit `0`; lineage contains
`datalake_ebdb_clean.listing_sale_model.sale_type`; no metadata reference to
`listing_sale_model.is_primary_market` remains for this derived column.

- [ ] **Step 6: Inspect and commit the functional change**

Run:

```bash
git diff --check
git diff -- dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql \
  dags/house_and_listing/enrich_ebdb_listing/metadata/enrich/house.yaml
```

Confirm the diff changes only the aggregation expression and the paired
metadata lineage/description. Commit:

```bash
git add \
  dags/house_and_listing/enrich_ebdb_listing/queries/enrich/house.sql \
  dags/house_and_listing/enrich_ebdb_listing/metadata/enrich/house.yaml
git commit -m "feat(aarede-481): derive house market from sale type"
```

## Task 2: Run the complete static pre-push gate

**Files:**

- Inspect: all files changed from `origin/master`
- Test: repository static validation commands below

**Interfaces:**

- Consumes: Task 1's committed SQL and metadata
- Produces: a clean, reviewable AAREDE-481 branch with no Forno claim

- [ ] **Step 1: Run repository style and lint checks**

```bash
make lint
make check-style
make check-style-dags
```

Expected: all commands exit `0`.

- [ ] **Step 2: Run source policy and LLM-context checks**

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-source-layer-policy
make validate-llm-context-dag-impact
```

Expected: both commands exit `0`. The LLM-context check should report no
broken golden-query references because the output column name is unchanged.

- [ ] **Step 3: Verify final scope and branch state**

```bash
git diff --check origin/master...HEAD
git diff --name-status origin/master...HEAD
git status --short --branch
```

Expected: functional diff contains only the house SQL and paired metadata,
plus the committed specification and implementation plan; no unrelated source
or generated DAG changes are present; the worktree is clean.

## Task 3: Push and open the draft pull request

**Files:**

- Inspect: committed branch diff and commit history
- Create externally: GitHub draft pull request linked to AAREDE-481

**Interfaces:**

- Consumes: clean branch from Task 2
- Produces: pushed `AAREDE-481/derive-house-primary-market` and a draft PR

- [ ] **Step 1: Run the pre-push PR review**

Use the repository pre-push review workflow against
`origin/master...HEAD`. It must cover changed-file scope, metadata pairing,
lineage, FAIR metadata, style, lint, source-layer policy, and EMR SQL
compatibility.

Expected: no blocking findings. Report Forno as pending because this delivery
does not run the DAG locally.

- [ ] **Step 2: Push the Jira-scoped branch**

```bash
git push -u origin AAREDE-481/derive-house-primary-market
```

Expected: the remote branch points to the local commits and GitHub accepts the
push.

- [ ] **Step 3: Create the draft PR**

Use this title:

```text
feat(aarede-481): derive house primary market from sale type
```

Use a body based on the repository PR template with:

- Why: replace legacy house classification with the `sale_type` source of truth
- Jira: `[AAREDE-481](https://quintoandar.atlassian.net/browse/AAREDE-481)`
- What: strict `PRIMARY` aggregation and metadata lineage update
- Tests: list only checks that actually passed
- Attention: production currently has 536 `PRIMARY` source rows, while legacy
  positives include rows with `sale_type IS NULL`; Forno remains pending
- Screenshots: `Not applicable — data pipeline change`
- Checklist: preserve the repository checklist with default unchecked states

Create the PR as draft, assign it to the authenticated user, and return its
canonical URL.
