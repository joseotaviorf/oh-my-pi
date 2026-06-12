---
name: databricks-emr-migration
description: >
  End-to-end workflow for migrating Airflow DAGs from Databricks to EMR Spark 3.5.
  Async parallel validation: submit → S3 poll → incremental report. SQL lint → rewrite → compare → hygiene → PR.
  MANDATORY completion contract: watch finalizes, syntax FAILs revalidated once, parity FAILs flagged (whole DAG
  excluded from PR), reports + MIGRATION_SUMMARY written, hygiene + PR for PR-eligible DAGs only.
  Use for "migrate to EMR", line/list scope, batch_validate.
---

# Databricks → EMR Migration

Translates Databricks-only SQL constructs to EMR Spark 3.5, validates output parity against
**production** on both runtimes (schema + volumetry ± 5%; optional deterministic sample via
`--with-sample`), updates cluster config, runs repo hygiene, and opens a PR.

## Skill-local CLI: `migration-emr-cli/`

The skill bundles its own EMR CLI fork under `migration-emr-cli/` (not `packages/emr-cli`).
Bootstrap once per machine:

```bash
cd .cursor/skills/databricks-emr-migration/migration-emr-cli
make sync
make build-executable   # optional; uv run migration-emr-cli also works
```

| Path | Role |
|------|------|
| `config/migration-validate.yml` | Glue metastore, Delta, client deploy-mode, validation cluster sizing |
| `samples/job/migration_validate_job.py` | PySpark driver: DESCRIBE + profile (+ sample) → S3 JSON |
| `src/emr/aws_auth.py` | Weep refresh + `call_with_aws_retry` |
| `src/emr/result_fetch.py` | S3 poll + `RESULT_JSON=` line parsing |
| `cli.py`, `config.py`, `emr_ops.py`, `staging.py` | Settings profile, step submit, staging |

## Completion contract *(non-negotiable)*

**A migration task is NOT done until every step below is executed or explicitly blocked with a written report.**  
Do **not** end the agent turn after submit, watch, cluster tuning, or infra debugging alone.

| # | Step | Done when |
|---|------|-----------|
| 1 | Bootstrap | Auth OK; user `--cluster`; `.session.yml` has `active_run_id` |
| 2 | Lint + translate | Critical greps zero; EMR preset in `{dag}_cluster.yml` |
| 3 | Submit + **watch completes** | Manifest: no `running`/`pending`; all jobs terminal |
| 4 | **Fix → revalidate loop** | **Syntax FAILs** fixed + one revalidate pass; parity FAILs flagged in report |
| 5 | **Final report** | Per-DAG `{dag}_{date}.md` + `MIGRATION_SUMMARY.md` updated |
| 6 | **User-facing summary** | PR-eligible vs blocked DAG tables; per-table DB/EMR/delta/verdict |
| 7 | Hygiene | `make validate-*` green for **PR-eligible DAGs only** |
| 8 | **PR for safe DAGs** | Open PR(s) via `create-or-update-pr` for DAGs with PASS/WARN only; list held/blocked DAGs separately |

**Forbidden exit states** (agent must continue or hand off with checklist):

- Watch crashed / detached died → restart watch; do not summarize as complete
- Parity FAIL exists → **flag DAG as Blocked**; do **not** block hygiene/PR for other DAGs
- Syntax FAIL remains after fix pass → fix SQL or document; still proceed with PR for safe DAGs
- Only partial reports exist → finalize watch first
- User asked an infra side-question (cluster size, deploy-mode, EMR UI) → answer, then **resume** steps 3–8

**When PR is blocked for a DAG** (≥1 FAIL table — whole DAG excluded):

1. List failing table(s) with one-line error and `retry: yes/no` (syntax vs parity)
2. Link to `reports/{domain}/{dag}_{date}.md`
3. Do **not** include that DAG's files in the PR diff

**When PR is held for a DAG** (≥1 MANUAL table — whole DAG excluded until re-validated):

1. List manual table(s) with timeout reason
2. Re-run with longer `--manual-check-timeout` before including in PR
3. Do **not** include that DAG's files in the PR diff

**End-of-batch deliverable** (mandatory):

1. Run hygiene for every **PR-eligible** DAG (PASS/WARN only — no FAIL, no MANUAL)
2. Open PR(s) for safe DAGs (`create-or-update-pr`; commit only when user asks)
3. Print **PR eligible**, **Held (manual)**, and **Blocked (FAIL)** summary tables
4. Never leave safe DAGs un-PR'd because another DAG failed

**When PR is allowed for a DAG**, invoke `create-or-update-pr` in the same session (commit only when user asks).

## Core loop

1. Run query on Databricks PROD (original SQL from `master`) → schema + count (+ sample with `--with-sample`)
2. Run translated query on EMR PROD (SQL from working tree) → schema + count (+ sample with `--with-sample`)
3. Compare → **OK** / **WARN** / **NOT OK** per table (schema + count + column profile by default)
4. Write markdown report + print summary table

**Single command (default after SQL rewrite):**

```bash
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag $DAG_NAME \
  --domain $DAG_DOMAIN \
  --cluster $DB_CLUSTER
```

Internally: **decoupled submit** (Databricks baseline + EMR step in parallel per table) → **S3 poll** → incremental report → final summary.

- Databricks baseline (git `master`) and EMR step (working tree) are **fired concurrently** per table; watch compares when both `.baseline.json` and `.emr.json` land on S3
- `--cluster` is **always required** for compare/submit (ask the user for a running all-purpose cluster id)
- Never run `databricks clusters list` or reuse `.session.yml` to pick a Databricks cluster
- `--table dim_x` for single-table debug
- `--with-sample` for deterministic 100-row sample compare (default: schema + profile; sample opt-in)
- `--no-profile` for legacy schema + count only (skips null counts and checksum)
- `--sync` for legacy blocking sequential compare (debug only)
- `--verbose` streams full EMR Spark logs (debug only; default is quiet)
- `--phase 2` / `--phase 4` remain for debugging; **`compare` is default**

**Massive migration (multi-DAG):**

```bash
# Single domain (line)
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --line fintech --phase submit --cluster $DB_CLUSTER

# Explicit cross-domain list (flag)
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope agents/enrich_agent,fintech/enrich_billing,growth/enrich_attribution \
  --phase submit --cluster $DB_CLUSTER

# Large batch (scope file)
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope-file migration_scope.yml --phase submit --cluster $DB_CLUSTER

# Resume interrupted submit on same run_id (skips DAGs already in manifest)
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope-file migration_scope.yml --phase submit --run-id $RUN_ID --cluster $DB_CLUSTER

# Recover after watch crash — reset stuck in-flight jobs, then resubmit
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope-file migration_scope.yml --phase submit --run-id $RUN_ID --cluster $DB_CLUSTER --reset-stale

# Poll S3 in background while continuing lint/translate work
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --phase watch --run-id $RUN_ID --detach
```

Scope file format (`migration_scope.yml`):

```yaml
- domain: agents
  dag: enrich_agent
- domain: fintech
  dag: enrich_billing
```

After watch completes, `batch_validate.py` and `validate.py --phase watch` print **PR eligible**, **Held (manual)**, and **Blocked** summary tables automatically.

Re-run `watch` (foreground) before PR if detached. **Do not mark DAG Migrated or open PR until watch completes.**

**Report (mandatory — never skip):**

After every compare run, agent MUST:

1. Print terminal summary table (table | DB rows | EMR rows | delta | verdict)
2. Write `reports/{domain}/{dag}_{date}.md` with blockers and sample diffs
3. Append DAG outcome to `reports/{domain}/MIGRATION_SUMMARY.md`:
   - **Migrated** — PASS/WARN only (PR-eligible)
   - **Migrated (warnings)** — WARN only, no FAIL/MANUAL
   - **Held (manual check)** — ≥1 MANUAL table (excluded from PR)
   - **Blocked** — ≥1 FAIL table (whole DAG excluded from PR)
   - **Skipped** — already `emr_*` cluster preset

**PR gate (DAG-level):**

```
pr_allowed = (failed == 0 and manual == 0)   # PASS/WARN only
one FAIL or one MANUAL table → whole DAG excluded from PR
IF pr_allowed AND repo hygiene green → include DAG in PR
ELSE → flag DAG in Held or Blocked list; continue with other DAGs
```

**Agent rules:**

- **Always ask the user** for a running Databricks all-purpose cluster id before compare/submit.
  Pass it as `--cluster`. Do **not** auto-discover clusters (`databricks clusters list`) or
  silently reuse `.session.yml` `databricks_cluster_id`.
- **Never run Phase 4 alone** without baselines — use default `compare` mode
- **Never finish a migration DAG** without the final markdown report (partial reports during watch are not PR-eligible)
- **Do not open PR** until `watch` completes for the `run_id` (store `run_id` in session after submit)
- **Always show** final OK/NOT OK table to the user, even when PR is blocked
- For line scope: use `batch_validate.py`; update `MIGRATION_SUMMARY.md` when watch finalizes per DAG

## Tooling rules *(prevent ad-hoc scripts)*

**Allowed entry points only:**

| Tool | Use for |
|------|---------|
| `validate.py` | Single DAG compare / submit / watch |
| `batch_validate.py` | Multi-DAG batch (`--line`, `--scope`, `--scope-file`) |
| `revalidate_failures.py` | Syntax FAIL retry on existing `run_id` |
| `create-or-update-pr` skill | PR for PR-eligible DAGs |

**Forbidden:**

- Creating `_*.py`, `_*.sh`, or any new script under this skill directory
- Hardcoding `run_id`, cluster ids, absolute paths, or DAG lists in throwaway helpers
- Shell wrappers that duplicate watch / hygiene / PR orchestration

**When stuck:** extend the official CLI (`batch_validate.py`, `manifest.py`, etc.) or document the gap in this skill — never add a one-off helper file.

**Related skills:**
- `databricks-emr-sql-lint` — SQL lint and rewrite recipes (do not re-implement)
- `create-or-update-pr` — PR creation
- `create-metadata-files` — metadata repair after column renames
- `right-size-cluster` — cluster preset sizing

See **VALIDATION.md** for compare rules, flags, and troubleshooting.

---

## Inputs & Filters

```
# Single DAG
migra dw_rent_contracts para EMR

# Explicit list
migra dw_rent_contracts, dw_sale_contracts, enrich_person para EMR

# Entire business line
migra for_rent para EMR
```

**Discovery filter (line scope):** Scan `dags/{line}/` and collect all DAG folders whose
`*_cluster.yml` has `cluster.type` that does **not** start with `emr_`.
Already-migrated DAGs are silently skipped.

**Batch scope selectors (equivalent — pick one for `batch_validate.py`):**

| Mode | CLI | Example |
|------|-----|---------|
| Line | `--line {domain}` | `--line agents` |
| Multi-DAG flag | `--scope domain/dag,...` | `--scope agents/enrich_agent,fintech/enrich_billing` |
| Multi-DAG file | `--scope-file path.yml` | `--scope-file migration_scope.yml` |

PR gating uses manifest verdicts for whichever scope was submitted — not the selector type.
Both line scope and multi-DAG scope produce the same PR-eligible vs Blocked tables after watch.

**Translation filter:** Only `.sql` files with at least one lint finding are rewritten; already
EMR-compatible files are left unchanged.

---

## Bootstrap *(once per session)*

### Authenticate

Run all auth commands automatically. Do not wait for the user to ask.

**Databricks (PROD):** `export DATABRICKS_CONFIG_PROFILE=PROD`; login if needed.

**AWS (EMR PROD):** `validate.py` calls `emr_runner.ensure_aws_credentials()` (delegates to
`migration-emr-cli/`). Settings profile: `EMR_SETTINGS_FILE=migration-emr-cli/config/migration-validate.yml`.
On `ExpiredToken`: `cd migration-emr-cli && EMR_ENVIRONMENT=prod make weep-auth`

### Clusters

Session state: `.cursor/skills/databricks-emr-migration/.session.yml`

- **Databricks:** ask the user for a running all-purpose cluster id and pass `--cluster` on every
  compare/submit run. The CLI validates it is `RUNNING` and not a `job-*` cluster. No listing,
  prompting, or session fallback — the agent must collect the id from the user first.
- **EMR:** dedicated `migration-emr-cli` cluster tagged `Purpose=migration-validation` (never fleet DAG clusters).
  Created/reused automatically by compare. Use `--new-emr-session` for a fresh cluster.

### Validation window

d-1 dates are computed automatically (`load_start_date` = yesterday, `load_end_date` = today).

---

## Lint

For each DAG in scope, run the ten critical greps from `databricks-emr-sql-lint/SKILL.md §Step 1`
on every SQL file. Print a findings summary table and proceed.

Only files with findings are rewritten. Re-run greps until zero critical findings remain.

---

## Translate

Apply `databricks-emr-sql-lint/RECIPES.md` recipes in order:

1. `col::TYPE` → `CAST(col AS TYPE)`
2. `SELECT * EXCEPT(...)` → explicit column list
3. Variant access → type-appropriate rewrite (check MCP)
4. `IFF` → `IF`, `DECODE` → `CASE WHEN`, `DATEDIFF(unit,...)` → `TIMESTAMPDIFF`
5. `GROUP BY ALL` → enumerate columns
6. `QUALIFY` → CTE + `WHERE rn = 1`
7. `WITH RECURSIVE` → **stop, surface to user**

Update `{dag}_cluster.yml` to EMR preset (`emr_7_12_consolidation_*`). See cluster mapping in
previous skill versions or `right-size-cluster` skill.

---

## Compare *(mandatory)*

```bash
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag $DAG_NAME --domain $DAG_DOMAIN --cluster $DB_CLUSTER
```

**Async flow (default):** decoupled `submit` → `watch` → report

| Phase | Command | Behavior |
|-------|---------|----------|
| submit | `--phase submit` | Fire Databricks baseline (master) and EMR step (working tree) **in parallel** per table; writes `manifest.json` + artifacts to S3 |
| watch | `--phase watch --run-id X` | Poll S3, compare per table when both artifacts exist, incremental report |
| compare | default | submit + foreground watch |

Submit pools: `max_parallel_databricks` (default 3) and `max_parallel_emr` (default 8). With `--with-sample`, tables that cannot resolve `order_by` without baseline fall back to coupled submit for that table only.

**Revalidate FAIL tables** (same `run_id`):

```bash
python .cursor/skills/databricks-emr-migration/revalidate_failures.py \
  --run-id $RUN_ID --databricks-cluster $DB_CLUSTER --emr-cluster $EMR_CLUSTER
```

Per-table failures/timeouts are **flagged and skipped** — they do not stop other tables.

S3 layout: `migration-validate/{run_id}/manifest.json`, `{domain}/{dag}/{layer}/{table}.baseline.json`, `.emr.json`

Outputs:
- Terminal live progress + final OK/NOT OK table
- `reports/{domain}/{dag}_{date}.md` (updates during watch)
- `reports/{domain}/MIGRATION_SUMMARY.md` (on watch finalize)
- `validation_results.json` (machine-readable, gitignored)

Exit code `0` → watch complete; proceed to hygiene/PR for eligible DAGs (parity FAIL OK).
Exit code `1` → syntax FAIL remains after fix pass, or watch crashed.

---

## Fix → revalidate loop *(syntax FAILs only)*

**This loop is part of the completion contract — not optional.**

When watch finishes with **EMR syntax FAIL** tables, fix SQL and revalidate once. **Parity FAILs** (count/schema/baseline) are **flagged only** — do not block the batch loop or PR for other DAGs.

**Retry-eligible (auto-revalidate):** EMR query parse/analysis errors only:

- `[PARSE_SYNTAX_ERROR]`, `ParseException`, `UNSUPPORTED_FEATURE`, `missing ')'`, `Syntax error at or near`
- EMR step failed before count (parse/analysis)

**Flag only (no auto-retry):** `count_delta`, `schema=fail`, baseline capture issues, infra (`AccessDenied` → MANUAL)

1. **Read blockers** — manifest verdicts or `reports/{domain}/{dag}_{date}.md` error snippets.
2. **Fix SQL** for syntax FAILs — apply `databricks-emr-sql-lint` recipes; common EMR-only failures:
   - `{{` / `}}` regex quantifiers (validation uses `pin_sql` brace collapse; keep `{{` in repo files)
   - window functions in `WHERE` → CTE + filter on computed column
   - lateral column alias in `OVER (PARTITION BY alias …)` → use source column name
   - `CURRENT_DATE` filters → `{load_end_date}` / incremental params
   - join fan-out → dedupe dimension CTE before join
   - infra (`AccessDenied` on S3 self-read) → **MANUAL**; fix IAM or skip with `--force-infra`
3. **Revalidate syntax FAILs only** (same `run_id`; default skips parity FAILs):

```bash
python .cursor/skills/databricks-emr-migration/revalidate_failures.py \
  --run-id $RUN_ID \
  --databricks-cluster $DB_CLUSTER

# Revalidate all FAIL types (legacy):
python .cursor/skills/databricks-emr-migration/revalidate_failures.py \
  --run-id $RUN_ID --databricks-cluster $DB_CLUSTER --all-failures
```

4. **Re-run watch** if you used `--submit-only`:

```bash
python .cursor/skills/databricks-emr-migration/validate.py \
  --phase watch --run-id $RUN_ID
```

5. Update `MIGRATION_SUMMARY.md` after watch pass. Proceed to hygiene + PR for DAGs with zero FAIL.

**Agent rules for the loop:**

- Fix and revalidate **syntax FAILs**; **flag** parity FAILs in report (whole DAG excluded from PR)
- Never mark a DAG **Migrated** while any table is FAIL
- Do not terminate the EMR validation cluster between fix iterations unless it is dead
- Print PR-eligible vs blocked DAG tables after every watch pass
- After watch, **always** run hygiene + PR for safe DAGs; never skip because other DAGs failed

---

## Repo hygiene *(per DAG that passed compare)*

```bash
CI_COMMIT_BRANCH=$(git branch --show-current)
make validate-metadata-files-exist    CI_COMMIT_BRANCH=$CI_COMMIT_BRANCH
make validate-metadata-files-content  CI_COMMIT_BRANCH=$CI_COMMIT_BRANCH
make validate-lineage-consistency     CI_COMMIT_BRANCH=$CI_COMMIT_BRANCH
make dependencies-file && git add dags/dependencies.yaml
make validate-dependency-file-correctness CI_COMMIT_BRANCH=$CI_COMMIT_BRANCH
```

---

## Open PR *(once per batch of passing DAGs)*

Invoke `create-or-update-pr` skill. Include validation report paths and per-table results.
List blocked DAGs from `MIGRATION_SUMMARY.md` in PR attention points.

---

## Session teardown

EMR validation cluster is not auto-terminated. Terminate manually when done:

```bash
cd .cursor/skills/databricks-emr-migration/migration-emr-cli
EMR_ENVIRONMENT=prod dist/migration-emr-cli terminate \
  --cluster-id "$(uv run python -c "import yaml; print(yaml.safe_load(open('../.session.yml'))['emr_cluster_id'])")"
```

---

## Quick-reference checklist

Use this before ending any migration turn. **All boxes must be checked or explicitly marked blocked.**

- [ ] Bootstrap: auth OK; user provided Databricks `--cluster`; d-1 dates set
- [ ] Lint: all SQL files scanned; rewrites applied
- [ ] Compare: submit + watch **finished** (not crashed, not stale detached)
- [ ] Fix → revalidate: **syntax FAILs** addressed; parity FAILs flagged (Blocked DAGs documented)
- [ ] Reports: per-DAG markdown + `MIGRATION_SUMMARY.md` + PR-eligible vs blocked tables shown
- [ ] Hygiene: `make validate-*` green (PR-eligible DAGs only)
- [ ] PR: opened for eligible DAGs + blocked DAGs listed separately
- [ ] Tooling: no ad-hoc `_*.py` / `_*.sh` scripts created under this skill directory
