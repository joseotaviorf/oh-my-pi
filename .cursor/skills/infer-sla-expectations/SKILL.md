---
name: infer-sla-expectations
description: >-
  Propose domain-owned SLA files for observability checks (`empty_partition`,
  `stale_data`). Combines producer DAG schedule and Trino partition history to
  onboard partitioned tables. Unpartitioned tables stay opt-out (no SLA file).
  Use when auto-filling sla/<layer>/<table>.yml files or onboarding tables to
  empty-partition / stale-data monitoring.
---

# Infer SLA Expectations

Proposes `sla/<layer>/<table>.yml` files for the empty-partition monitor
([design spec](../../docs/superpowers/specs/2026-08-04-empty-partition-sla-design.md)).

Governance owns the monitor; **domain teams own SLA values**. This skill proposes;
the domain approves via PR (`CODEOWNERS` routes `dags/<domain>/**`).

---

## When to use

- A table generates false-positive empty-partition alerts on weekends or before the
  expected load hour.
- Bulk onboarding noisy tables after the monitor ships.
- User asks to "infer SLA", "auto-fill arrival SLA", or "reduce empty partition noise".
- An **unpartitioned** table is alerting (or would alert) — mute it; do not invent a
  calendar SLA (see **§1a**).

---

## Prerequisites

1. **Trino access** — bounded partition-history queries (see **§2**). Prefer **Trino MCP**
   (`plugin-trino-mcp-Trino MCP`: `describe_table`, `execute_query`). **Do not** use `@tars`
   or the TARS persistence loop (`tars_query_results/`, `data_exploration.mdc`) for this
   workflow — it is operational inference, not ad-hoc analysis.
2. **Table identity** — know `database_name`, `table_name`, producing DAG folder, and layer.
3. **Metadata** — read `metadata/<layer>/<table>.yml` for `database_name` / `table_name`
   (do not duplicate `owner` in the SLA file).

---

## Trino access (prefer MCP)

1. **Trino MCP** (`plugin-trino-mcp-Trino MCP`): if the server needs auth, call `mcp_auth`
   with `{}` via `CallMcpTool` before the first query. Use fully qualified names
   (`hive.<schema>.<table>`).
2. **`describe_table`** — confirm **physical** `year` / `month` / `day` partition columns
   before running history SQL. If none exist, stop cadence inference and follow **§1a**.
3. **`execute_query`** — run the cadence SQL below (aggregates only; never `SELECT *`).
4. **Fallback** if MCP is unavailable or still fails after auth: `uv run --script
   .cursor/skills/trino/scripts/execute_trino.py` with `--external-auth` (same pattern as
   `scripts/infer_governance_sla_files.py`). See [`trino` skill](../trino/SKILL.md) for flags
   only — **do not** require `@tars` for this skill.

Chat preview of query results is enough; do not write TARS result files.

---

## Input scope

Accept one of:

| Input | Action |
|-------|--------|
| Single table | `database_name.table_name` or path to `metadata/<layer>/<table>.yml` |
| DAG | All **physically partitioned** tables in `queries/<layer>/` for that DAG; mute any unpartitioned ones per **§1a** |
| Domain folder | All DAGs under `dags/<domain>/` (batch; prefer DAG-by-DAG PRs) |

---

## Workflow

### 1. Resolve producer context

For each target table:

1. Locate the producing DAG folder (`dags/<domain>/<dag>/`).
2. Read `metadata/<layer>/<table>.yml` → `database_name`, `table_name`.
3. Read `<dag>_declaration.yml` → `dag.schedule_interval` (cron).
4. Decide **partitioned vs unpartitioned** using **§1a** (hard gate before §2).

### 1a. Unpartitioned tables — opt-out, do not alert

Empty-partition monitoring is **only** for tables with a real partition grain (typically
`year` / `month` / `day`). Unpartitioned tables must **not** receive SLA files.

**Why opt-out is required:** without an SLA file (or without an `empty_partition` check),
the judge does not alert. Profiling no longer invents partition keys from DAG
`default_partitions` when Delta `partitionColumns` is empty.

**Treat as unpartitioned when any of these hold** (physical truth wins over DAG
defaults):

| Signal | Unpartitioned if… |
|--------|-------------------|
| Trino / metastore | No partition columns on `describe_table` / table detail |
| Delta | `partitionColumns` empty (or equivalent DESCRIBE DETAIL) |
| Declaration | Effective partitions are `[]` (per-table `partitions: []` overrides `default_partitions`) **and** load/SQL writes the full table (e.g. MERGE without `partition_by`) |
| Schema / load | No `year`/`month`/`day` partition layout; full-table overwrite/MERGE |

When unpartitioned: **skip §2–§5**. Do **not** create `sla/<layer>/<table>.yml`.

### 2. Query Trino for partition history (~8 weeks)

Use **Trino MCP** `execute_query` (preferred) or the `execute_trino.py` fallback. Example
pattern (adjust catalog/schema for environment):

```sql
SELECT
    CAST(year AS integer) AS year,
    CAST(month AS integer) AS month,
    CAST(day AS integer) AS day,
    COUNT(*) AS row_count
FROM hive.<database_name>.<table_name>
WHERE DATE(CAST(year AS varchar) || '-' ||
           LPAD(CAST(month AS varchar), 2, '0') || '-' ||
           LPAD(CAST(day AS varchar), 2, '0')) >= CURRENT_DATE - INTERVAL '56' DAY
GROUP BY 1, 2, 3
HAVING COUNT(*) > 0
ORDER BY 1, 2, 3
```

Derive partition cadence context for the PR description (weekday histogram). The
`checks[]` contract no longer stores `days_of_week` or `earliest_hour`.

### 3. Read dependencies for consistency

Open `dags/dependencies.yaml`:

- **Upstream** — if the producer DAG depends on upstreams that only run on business
  days, weekend emptiness downstream is expected.
- **Downstream** — sanity-check that inferred cadence is consistent with consumers.

Use dependency keys like `bietlejuice.<dag_name>` and task suffixes
(`:first-run-of-day`, `:load-clean-*`).

### 4. Derive optional stale_data fields

| Field | Source | Rule |
|-------|--------|------|
| `column` | Metadata / domain | Operational timestamp (`ts_*`) that reflects freshness |
| `max_age_hours` | Cron + domain SLA | Hours since MAX(column); no auto-inference in bulk onboarding |

Domain validation happens via the normal PR review (`CODEOWNERS`).

### 5. Write the SLA file

Path: `dags/<domain>/<dag>/sla/<layer>/<table>.yml`

Template (empty partition only):

```yaml
database_name: <from metadata>
table_name: <from metadata>

checks:
  - type: empty_partition
```

Optional stale-data check (domain must pick column and threshold):

```yaml
checks:
  - type: empty_partition
  - type: stale_data
    column: ts_load
    max_age_hours: 36
```

**Do not** add `owner` — ownership lives in `metadata/`.

### 6. Validate locally

```bash
uv run --directory packages/bietlejuice-core pytest \
  test/unit/observability/monitoring/test_sla_expectations.py -q
```

Optionally dry-run the loader against the repo root:

```bash
uv run python -c "
from bietlejuice.observability.monitoring.sla_expectations import load_sla_expectations
print(len(load_sla_expectations('dags')))
"
```

### 7. Open PR

Use [`create-or-update-pr`](../create-or-update-pr/SKILL.md). PR title example:

```
feat(<domain>): add SLA checks for <table_name>
```

PR description must include:

- Observed weekday histogram (from Trino).
- Producer cron and upstream dependencies consulted.
- For `stale_data`: column choice and `max_age_hours` rationale.
- Note: **no SLA file = no alert** (opt-in checks).

`CODEOWNERS` routes review to the domain team (e.g. `dags/people/**` →
`@quintoandar/enterprise-engineering`).

---

## Rollout guidance

1. Start with the **noisiest** tables (most empty-partition alerts in GChat).
2. Prefer **small PRs** (one DAG or ≤10 tables) for faster review via `CODEOWNERS`.
3. **Do not** create SLA files for **unpartitioned** tables (§1a).
4. Add `stale_data` only when the domain can name column + threshold.

---

## Out of scope

- Changing the empty-partition **judge** to skip when `rows_written > 0` (keep
  inventory `row_count` as the trigger; use opt-out / correct partitioning for
  unpartitioned false positives).
- `dag_sla_information` migration (Phase 2 —
  `docs/superpowers/specs/2026-08-04-dag-sla-migration-phase2-design.md`).
- `freshness` / `volume` facets (schema allows; not implemented in v1).
- Holiday-aware or monthly cadences.

---

## Reference

- Design: `docs/superpowers/specs/2026-08-04-empty-partition-sla-design.md`
- Loader: `packages/bietlejuice-core/src/bietlejuice/observability/monitoring/sla_expectations.py`
- Judge: `packages/bietlejuice-core/src/bietlejuice/observability/monitoring/empty_partition.py`
- Monitor DAG: `dags/governance/data_observability_monitoring/`
