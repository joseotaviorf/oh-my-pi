---
name: find-stale-dags
description: >-
  Identify stale Airflow DAGs in QuintoAndar's production environment using Trino.
  A DAG is stale when it has no successful run in the last 6 months or has never
  succeeded. Queries datalake_astro_clean tables via the Trino cluster and presents
  results grouped by owner. Use when the user asks to find stale DAGs, check which
  DAGs are inactive, audit unused pipelines, or investigate the stale DAG report
  (DPLT-860).
---

# Find Stale DAGs

Queries production Airflow metadata (via Trino → `datalake_astro_clean`) to surface
active, unpaused DAGs that have not had a successful run in **6 months** or more.

---

## Prerequisites

Only **[uv](https://docs.astral.sh/uv/)** is required. The query script declares its
dependencies inline (PEP 723: `trino`, `keyring`), so `uv run --script` resolves them from
the global uv cache on first run and reuses them afterwards — there is no venv to bootstrap
and nothing is written under the skill folder. Never run bare `python3` or `pip install`.

---

## Workflow

### 1. Run the canonical query

```bash
uv run --script .cursor/skills/find-stale-dags/scripts/run_query.py
```

The script prints a formatted table and exits.

**OAuth2 SSO note:** On each run, the script prints a URL like:
```
Open the following URL in browser for the external authentication: https://trino.apps.…
```
Open that URL in your browser, complete the SSO login, then **re-run the script** — the
token is cached by `keyring` so subsequent runs won't need the browser step.

Optional flags:
- `--months N` — change the staleness threshold (default: 6)
- `--no-filter` — include event-driven and manually-triggered DAGs in output

### 2. Interpret the results

| Column | Meaning |
|--------|---------|
| `months_since_last_success` | `NULL` = never succeeded |
| `schedule_interval` | `"null"` or `"Dataset"` = manually triggered or event-driven |
| `owners` | Airflow owner tag (maps to data squad) |

**Expected exclusions** — these are not truly stale by definition:
- `schedule_interval = "Dataset"` or `"null"` → event-driven / manual DAGs
- DAG IDs starting with `quintoml.` → MLOps on-demand inference/training jobs

The `notify_stale_dags` DAG already filters these out before sending GChat alerts.

### 3. Summarise and report

Group results by `owners`. Share the summary in the GChat channel via the
`notify_stale_dags` DAG or paste directly.

---

## Canonical Trino Query

Direct partition pushdown is required — `DATE(format(...)) = current_date` does **not**
prune partitions and returns empty results. Always use explicit `year/month/day` filters.

```sql
WITH last_success AS (
    SELECT
        id_dag,
        MAX(ts_started) AS ts_last_success
    FROM datalake_astro_clean.dag_run
    WHERE state = 'success'
    GROUP BY 1
),
last_serialized AS (
    SELECT
        id_dag,
        MAX(ts_last_updated) AS ts_last_serialized
    FROM datalake_astro_clean.serialized_dag
    GROUP BY 1
)
SELECT
    d.id_dag,
    d.owners,
    d.schedule_interval,
    ls.ts_last_success,
    lz.ts_last_serialized,
    date_diff('month', ls.ts_last_success, current_date) AS months_since_last_success,
    date_diff('month', lz.ts_last_serialized, current_date) AS months_since_last_change
FROM datalake_astro_clean.dag d
LEFT JOIN last_success ls ON d.id_dag = ls.id_dag
LEFT JOIN last_serialized lz ON d.id_dag = lz.id_dag
WHERE d.year  = year(current_date)
  AND d.month = month(current_date)
  AND d.day   = day(current_date)
  AND d.is_active  = TRUE
  AND d.is_paused  = FALSE
  AND (
      ls.ts_last_success IS NULL
      OR ls.ts_last_success < date_add('month', -6, current_date)
  )
ORDER BY months_since_last_success DESC NULLS FIRST
LIMIT 200
```

To change the threshold, replace every `-6` with the desired number of months.

---

## Related files

| Path | Purpose |
|------|---------|
| `dags/platform/enrich_stale_dags/` | Weekly Databricks job that materialises the table |
| `dags/platform/notify_stale_dags/notify_stale_dags.py` | GChat notifier triggered after enrich |
| `metadata/enrich/stale_dags.yml` | Data governance for the materialised table |

Jira ticket: [DPLT-860](https://quintoandar.atlassian.net/browse/DPLT-860)
