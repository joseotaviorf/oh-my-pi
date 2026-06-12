# Validation Workflow — Compare (Databricks vs EMR)

End-to-end validation for Databricks → EMR migration. Default mode is **async**: parallel submit, S3 poll, incremental report, final compare summary.

> **Completion contract:** see `SKILL.md §Completion contract`. Validation alone does not finish a migration — fix syntax FAILs (one revalidate pass), flag parity FAILs (whole DAG excluded from PR), write reports, then hygiene + PR for PR-eligible DAGs only.

## Quick compare (default)

```bash
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis \
  --domain fintech \
  --cluster <YOUR_RUNNING_ALL_PURPOSE_CLUSTER_ID>
```

This automatically (async submit + foreground watch):

1. Submits **in parallel per table**: Databricks baselines (**git `master`**) and EMR steps (**working tree**) — neither waits for the other
2. Polls S3 for `.baseline.json` and `.emr.json` artifacts
3. Compares schema, count (±5%), and column profile (null counts + checksum thresholds) per table as results land (sample only with `--with-sample`)
4. Rewrites `reports/{domain}/{dag}_{date}.md` incrementally; finalizes `MIGRATION_SUMMARY.md` when done
5. Prints live progress + final OK / NOT OK summary table

Use `--sync` for legacy blocking sequential compare (debug). Add `--with-sample` for full schema + profile + sample on small/fast tables. Use `--no-profile` to skip null/checksum profiling (count-only legacy mode).

Example output:

```
Table                         | DB rows | EMR rows | Delta | Schema | Null | Chk | Sample | Verdict
------------------------------+---------+----------+-------+--------+------+-----+--------+--------
dim_drop_reason               | 197     | 197      | 0.0%  | ok     | ok   | ok  | skip   | OK

DAG dw_credit_analysis: 14 OK, 0 WARN — PR allowed
Report: .cursor/skills/databricks-emr-migration/reports/fintech/dw_credit_analysis_2026-06-05.md
```

Use `--verbose` to stream full EMR Spark logs (debug only). Default is quiet progress lines only.

## Async phases (massive migration)

```bash
# Submit only — returns run_id quickly
python .cursor/skills/databricks-emr-migration/validate.py \
  --phase submit --dag dw_credit_analysis --domain fintech --cluster <ID>

# Watch (foreground)
python .cursor/skills/databricks-emr-migration/validate.py \
  --phase watch --run-id <RUN_ID>

# Watch detached (background subprocess)
python .cursor/skills/databricks-emr-migration/validate.py \
  --phase watch --run-id <RUN_ID> --detach

# Entire line
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --line fintech --phase submit --cluster <ID>
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --phase watch --run-id <RUN_ID> --detach

# Cross-domain scope (flag or file)
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope agents/enrich_agent,fintech/enrich_billing --phase submit --cluster <ID>
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope-file migration_scope.yml --phase submit --cluster <ID>

# Resume submit on existing run_id (skips DAGs already in manifest)
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope-file migration_scope.yml --phase submit --run-id <RUN_ID> --cluster <ID>

# Reset stuck in-flight jobs after watch crash, then resubmit
python .cursor/skills/databricks-emr-migration/batch_validate.py \
  --scope-file migration_scope.yml --phase submit --run-id <RUN_ID> --cluster <ID> --reset-stale
python .cursor/skills/databricks-emr-migration/revalidate_failures.py \
  --run-id <RUN_ID> --reset-stale --databricks-cluster <ID>
```

## Fix → revalidate (syntax FAILs by default)

After watch reports FAIL tables, fix **EMR syntax** errors and re-run validation on the **same `run_id`**:

```bash
python .cursor/skills/databricks-emr-migration/revalidate_failures.py \
  --run-id <RUN_ID> --databricks-cluster <ID> --emr-cluster <EMR_ID> --detach-watch
```

- Default: resets only jobs whose `verdict` is FAIL **and** error is EMR syntax (parse/analysis).
- **`--all-failures`**: also revalidate parity FAILs (count/schema/baseline).
- Pass **`--emr-cluster`** to reuse a running validation cluster (avoids creating a new one).
- Skips infra failures (`AccessDenied` on S3) as `manual_check` unless `--force-infra`.
- Parity FAILs (count delta, schema mismatch) are **flagged** — whole DAG excluded from PR; batch continues.

### Failure taxonomy

| Kind | Examples | Auto-retry? | DAG PR? |
|------|----------|-------------|---------|
| Syntax | `PARSE_SYNTAX_ERROR`, `UNSUPPORTED_FEATURE`, `missing ')'` | Yes | No (if still FAIL) |
| Parity | `count_delta`, `schema=fail`, baseline empty | No | No |
| Infra | `AccessDenied`, S3 IAM | No (MANUAL) | No (held) |
| Timeout | exceeded manual check threshold | No | No (held) |

Repeat syntax fix → revalidate until **no syntax FAIL** remains. Parity FAILs do not block PR for other DAGs.

Exit code: **`0`** when watch completes (parity FAIL OK); **`1`** if syntax FAIL remains or watch crashed.

S3 artifacts under `migration-validate/{run_id}/`:

- `manifest.json` — job statuses
- `{domain}/{dag}/{layer}/{table}.baseline.json` — Databricks capture
- `{domain}/{dag}/{layer}/{table}.emr.json` — EMR result (legacy `.json` also read)
- `report/{domain}/{dag}.md` — live report mirror

## Module layout

| Module | Role |
|--------|------|
| `validate.py` | CLI entrypoint (`compare` / `submit` / `watch`) |
| `batch_validate.py` | Multi-DAG batch submit + watch (`--line`, `--scope`, `--scope-file`; resume via `--run-id`; `--reset-stale`) |
| `async_runner.py` | Parallel fire-and-forget submit |
| `poller.py` | S3 poll loop + incremental compare |
| `manifest.py` | Run manifest on S3 |
| `report.py` | Terminal summary + batch PR-gate tables + partial/final markdown reports |
| `databricks_client.py` | Commands API 1.2 + result parsing |
| `baseline.py` | Databricks baseline capture + S3 mirror |
| `emr_validation.py` | Sync EMR steps (`--sync` path) |
| `emr_runner.py` | migration-emr-cli bridge + S3 upload/poll helpers |
| `compare.py` | PASS/WARN/FAIL rules |
| `cluster_bootstrap.py` | Databricks + EMR cluster reuse; session updates |

**EMR runtime (owned by `migration-emr-cli/`):**

| migration-emr-cli piece | Role |
|---------------|------|
| `config/migration-validate.yml` | Migration profile (`CONTINUE`, Glue hive-site, staging URI) |
| `samples/job/migration_validate_job.py` | PySpark driver (reads SQL from S3, writes JSON result) |
| `stage` / `submit-step` / `list-clusters` / `describe-cluster` | Staging, steps, cluster discovery |
| `src/emr/aws_auth.py` / `result_fetch.py` | STS refresh + S3 result polling |

See `migration-emr-cli/README.md` for command reference.

Generated artifacts (gitignored): `baseline/`, `reports/`, `watchers/`, `validation_results.json`, `.session.yml`

## Debug modes

```bash
# Databricks baseline only (optional --git-ref, compare defaults to master)
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis --domain fintech \
  --cluster <CLUSTER_ID> --phase 2

# EMR compare only (requires baselines on disk)
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis --domain fintech --phase 4

# Single table
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis --domain fintech \
  --cluster <CLUSTER_ID> --table dim_drop_reason
```

## Quick Start (legacy phase flags)

```bash
# Phase 2 — requires a running all-purpose Databricks cluster id
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis \
  --domain fintech \
  --profile PROD \
  --cluster <YOUR_RUNNING_ALL_PURPOSE_CLUSTER_ID> \
  --git-ref master \
  --phase 2

# Phase 4 — EMR cluster optional (reuses session cluster or creates one)
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis \
  --domain fintech \
  --phase 4

# Single table debug
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis \
  --domain fintech \
  --profile PROD \
  --cluster <CLUSTER_ID> \
  --phase 2 \
  --table dim_drop_reason
```

## Cluster bootstrap

**Databricks (Phase 2):** `--cluster` is **always required**. Ask the user for a running
all-purpose cluster id and pass it on every compare/submit run. The CLI validates the cluster is
`RUNNING` and rejects `job-*` names. It does **not** list clusters, prompt interactively, or
fall back to `.session.yml`.

**EMR (Phase 4):** Always use a **dedicated migration-emr-cli cluster** (`Purpose=migration-validation`).
Step logs land under `emr/logs/cli/` so `--follow-logs` and S3 fetch work. **Never** submit to
fleet `bietlejuice.*` clusters (their LogUri is `emr/logs/dags/...`).

Resolution order (`resolve_validation_emr_cluster`):
1. `--new-emr-session` → create fresh migration-emr-cli cluster
2. `--emr-cluster` if `WAITING`/`RUNNING`
3. `.session.yml` `emr_cluster_id` if tagged `migration-validation` and reusable
4. Any active cluster tagged `Purpose=migration-validation`
5. `migration-emr-cli create-cluster` (default when no session cluster exists)

```bash
# New migration validation session (recommended at Phase 4 start)
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis --domain fintech --phase 4 --new-emr-session
```

**Step failure policy:** `action_on_failure: CONTINUE` — failed tables do not terminate the host cluster.

**Failover:** if the validation cluster is `TERMINATING`, create a new migration-emr-cli cluster (never fleet).

**Default validation cluster** (`migration-emr-cli/config/migration-validate.yml`):

| Role | Type | Count | Notes |
|------|------|-------|-------|
| Primary (master) | `m7g.2xlarge` | 1 | With **`deploy_mode: client`** (this profile), AWS documents the Spark **driver** on the primary node ([Add a Spark step](https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-spark-submit-step.html)). YARN **Application Master** still runs on a **core** node, not primary. |
| Core | `m7g.2xlarge` | 3 | Executors; also where the driver runs when using **`deploy_mode: cluster`** (production `prod.yml`). |

**Not the same as prod DAG runs:** fleet/production submits use `deploy_mode: cluster` — driver + AM on a core/task container ([Spark on YARN](https://github.com/apache/spark/blob/master/docs/running-on-yarn.md), [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/submitting-user-applications-with-spark-submit/)). Validation intentionally uses **client** mode for step-log visibility and async S3 results.

Sized above `emr_7_12_consolidation_m_general` (1 core + 1 task) for executor throughput. **Config changes apply only to new clusters** — pass `--new-emr-session` after editing the YAML. Cluster size does **not** fix planner hangs from `OR` in join conditions (rewrite SQL instead).

## Phase 2: Databricks PROD baseline

For each SQL file:

1. Load SQL from disk or `--git-ref` (use `master` for pre-rewrite baseline)
2. Pin `{load_start_date}`, `{load_end_date}`, `NOW()`, `CURRENT_DATE()`
3. Run on Databricks via Commands API 1.2:
   - `DESCRIBE ({sql})`
   - **Profile query** (default): `COUNT(*)` + per-column `COUNT_IF(null)` + fixed-width checksum in one scan
   - `SELECT COUNT(*) …` only when `--no-profile`
   - `SELECT * FROM ({sql}) ORDER BY {order_cols} LIMIT 100` — **only when `--with-sample`**
4. Save JSON to `baseline/{domain}/{dag}/{table}.json`

Baseline JSON includes `load_start_date`, `load_end_date`, `sql_hash`, `pinned_sql`, `schema`, `count`, `profile` (null counts + checksum per column), `sample` (empty when sample skipped), `order_by_cols`, `non_comparable_cols`.

**Load window parity:** Compare mode computes a fresh d-1 window on every run (`load_start_date` = yesterday, `load_end_date` = today). Baselines are reused only when both dates match the stored window; otherwise Phase 2 re-captures from Databricks automatically. Legacy baseline files without `load_end_date` are treated as stale. EMR Phase 4 pins SQL via `resolve_pin_dates()` to the same window as the baseline (never reuses `load_start_date` as the end date).

## Hive / Glue metastore (required)

EMR validation must resolve `datalake_*` tables via the AWS Glue Data Catalog (same as
production DAGs). Three layers must align:

1. **EMR cluster** — `hive-site` + `spark-hive-site` with Glue factory class and
   `spark.sql.catalogImplementation=hive` in `spark-defaults`
   (`migration-emr-cli/config/migration-validate.yml`).
2. **PySpark driver** — `migration-emr-cli/samples/job/migration_validate_job.py` mirrors
   bietlejuice `create_emr_spark_session`: Delta catalog + `.enableHiveSupport()`.
3. **Dedicated validation clusters** — tagged `Purpose=migration-validation` via migration-emr-cli
   (never fleet `bietlejuice.*` clusters).

Without `enableHiveSupport()`, Spark uses an in-memory catalog and fails with
`TABLE_OR_VIEW_NOT_FOUND` for Glue databases.

## Phase 4: EMR PROD validation

For each table (post-rewrite SQL from disk):

1. `migration-emr-cli stage` — upload pinned SQL to `migration-validate/{run_id}/{domain}/{dag}/{layer}/{table}.sql`
2. `migration-emr-cli submit-step --no-wait --deploy-mode client` (async) or `--wait --wait-result` (`--sync`)
3. Driver writes validation JSON to `migration-validate/{run_id}/{domain}/{dag}/{layer}/{table}.emr.json`
4. migration-emr-cli polls S3 and prints `RESULT_JSON=...` on stdout (no EMR step-log upload wait)
5. Compare against Phase 2 baseline

## Comparison rules

| Metric | Pass | Warn | Fail | Notes |
|--------|------|------|------|-------|
| Schema | Exact match | Type widening (`int`→`bigint`) | Missing/extra columns | Always |
| Count | Δ ≤ 0.1% | 0.1% < Δ ≤ 5% | Δ > 5% | Always |
| Null counts | All columns exact | — | Any column mismatch | Default profile |
| Checksum | Exact hex match | Sum delta 0.1–5% | Sum delta > 5% | Default profile; `ts_load` checksum skipped |
| Sample | Row match (excluding `ts_load`) | Minor float diffs | Structure mismatch | Only with `--with-sample` |

Exit code `0` = watch complete; proceed to hygiene/PR for DAGs with zero FAIL. Exit code `1` = syntax FAIL remains or watch crashed.

## Manual check (long-running tables)

Heavy fact queries (e.g. `fact_proposal_credit_flows`) may exceed the default runtime
threshold. Instead of blocking the whole DAG as **NOT OK**, the skill:

1. Marks the table **MANUAL** after `--manual-check-timeout` seconds (default **300**)
2. Skips further compare for that table
3. Lists it under **Manual check required** in the report
4. Holds the DAG from PR when any table is **MANUAL** — re-validate with longer timeout before merge

Re-validate flagged tables individually:

```bash
python .cursor/skills/databricks-emr-migration/validate.py \
  --dag dw_credit_analysis --domain fintech \
  --table fact_proposal_credit_flows \
  --cluster <ID> \
  --timeout 3600 --manual-check-timeout 7200 --job-timeout 7200
```

Databricks baseline timeouts during submit (`Command timeout after Ns`) are treated the same way.

## CLI flags

| Flag | Purpose |
|------|---------|
| `--cluster` | Running Databricks all-purpose cluster (required for compare/submit) |
| `--emr-cluster` | Explicit migration-validation EMR cluster id |
| `--new-emr-session` | Create fresh migration-emr-cli cluster (LogUri `cli/`) |
| `--git-ref master` | Phase 2: read pre-rewrite SQL from git |
| `--table` | Single-table validation |
| `--timeout 300` | Databricks baseline timeout (seconds); exceeded → manual check |
| `--with-sample` | Also capture and compare deterministic 100-row sample (default: schema + profile) |
| `--no-profile` | Legacy schema + count only (skip null counts and checksum) |
| `--no-create-emr` | Fail if no existing migration-validation session cluster |
| `--staging-uri` | Override S3 staging prefix |
| `--phase submit\|watch` | Explicit async phases |
| `--run-id` | Resume or watch an existing batch |
| `--detach` | Background watch subprocess after submit |
| `--sync` | Legacy blocking sequential compare |
| `--poll-interval 15` | S3 poll cadence (watch) |
| `--job-timeout 3600` | Per-table hard wall clock timeout (seconds) |
| `--manual-check-timeout 300` | Skip table and flag **MANUAL** after this threshold (default: 300) |
| `--max-parallel 5` | Parallel submit workers |

## AWS credentials (weep)

Phase 4 requires PROD EMR access. The skill refreshes credentials automatically:

1. `emr_runner.ensure_aws_credentials()` — STS check before Phase 4, cluster resolution, staging, each step
2. On `ExpiredToken` during S3 fetch — `migration-emr-cli` `call_with_aws_retry()` runs `make weep-auth` once and retries

Manual refresh (same as the skill):

```bash
cd migration-emr-cli && EMR_ENVIRONMENT=prod make weep-auth
aws sts get-caller-identity
```

Credentials last ~1 hour. Long multi-table runs refresh before each step to avoid mid-poll expiry.

## Troubleshooting

- **ExpiredToken / invalid AWS credentials:** handled by `migration-emr-cli` `aws_auth.py`; if refresh fails, complete ConsoleMe SSO in the browser and re-run.
- **Databricks auth conflict:** unset `DATABRICKS_USERNAME` when using PAT; CLI handles this automatically.
- **Large SQL / EMR CLI failure:** SQL is always staged to S3; only `--sql-s3-uri` is passed to the job.
- **Results during Phase 4:** the Spark driver writes JSON to
  `staging_uri/migration-validate/{run_id}/{domain}/{dag}/{table}.json` as soon as the query
  finishes. migration-emr-cli `--wait-result` reads that object directly — no wait for EMR step-log upload.
- **Missing result object:** check the EMR step state and S3 permissions on `staging_uri`. Use
  `--verbose` to stream step logs, or `migration-emr-cli dump-logs cli/<cluster>/steps/<step>/stdout.gz`.
- **Heavy DW queries:** default (schema + count only) avoids sample timeouts on large full-load tables. Re-validate individually with longer timeouts if needed: `--timeout 3600 --manual-check-timeout 3600 --job-timeout 3600`. Add `--with-sample` only for small/fast tables.

## Unit tests

```bash
cd .cursor/skills/databricks-emr-migration
python -m unittest discover -s tests -p 'test_*.py' -v
```
