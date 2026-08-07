---
name: infer-sla-expectations
description: >-
  Propose domain-owned arrival SLA files for empty-partition monitoring. Combines
  producer DAG schedule, Trino partition history, and dependencies.yaml to infer
  days_of_week and earliest_hour, then opens a PR for domain review. Use when
  auto-filling sla/<layer>/<table>.yml files, reducing empty-partition alert
  noise, or onboarding tables to calendar-aware SLAs.
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
2. **`describe_table`** — confirm `year` / `month` / `day` partition columns before
   running history SQL.
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
| DAG | All partitioned tables in `queries/<layer>/` for that DAG |
| Domain folder | All DAGs under `dags/<domain>/` (batch; prefer DAG-by-DAG PRs) |

---

## Workflow

### 1. Resolve producer context

For each target table:

1. Locate the producing DAG folder (`dags/<domain>/<dag>/`).
2. Read `metadata/<layer>/<table>.yml` → `database_name`, `table_name`.
3. Read `<dag>_declaration.yml` → `dag.schedule_interval` (cron).
4. Confirm the table is partitioned (`year`/`month`/`day` in declaration or metadata).

### 2. Query Trino for observed cadence (~8 weeks)

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

Derive **observed weekdays**: map each partition date to `mon`…`sun`; the set of
weekdays with at least one non-empty partition in the lookback window becomes the
candidate `days_of_week` list.

### 3. Read dependencies for consistency

Open `dags/dependencies.yaml`:

- **Upstream** — if the producer DAG depends on upstreams that only run on business
  days, weekend emptiness downstream is expected.
- **Downstream** — sanity-check that inferred cadence is consistent with consumers.

Use dependency keys like `bietlejuice.<dag_name>` and task suffixes
(`:first-run-of-day`, `:load-clean-*`).

### 4. Derive SLA fields

| Field | Source | Rule |
|-------|--------|------|
| `days_of_week` | Trino history (primary) | Weekdays with observed data in lookback |
| `earliest_hour` | Cron hour + buffer | Cron start hour + ~1–2 h completion lag (America/Sao_Paulo) |
| `reason` | All sources | Human-readable line citing cron, Trino, and any inference caveats |
| `source` | — | `inferred` or `manual` (documentation only; loader ignores it) |

**Conflict rule (history wins):**

- If Trino shows data on a weekday the cron does not cover (e.g. Saturday data but
  cron `0 9 * * 1-5`), emit the **observed** `days_of_week` and document the conflict
  in `reason` (e.g. `note: observed weekend partitions but cron is weekdays-only`).
- If history is sparse (< 4 weeks of data), still infer and add a `note:` in `reason`.

Domain validation happens via the normal PR review (`CODEOWNERS`); do not add
`reviewed_by` or `# REVIEW:` YAML comments.

### 5. Write the SLA file

Path: `dags/<domain>/<dag>/sla/<layer>/<table>.yml`

Template:

```yaml
database_name: <from metadata>
table_name: <from metadata>

arrival:
  days_of_week: [mon, tue, wed, thu, fri]   # or weekdays / all
  earliest_hour: 9
  reason: "Upstream ebdb_contract_fast_lane runs 0 9 * * 1-5; observed data Mon-Fri"
  source: inferred
```

**Do not** add `owner` — ownership lives in `metadata/`.

For full suppression (replaces legacy `empty_partition_suppression.yml`):

```yaml
arrival:
  mute: true
  reason: "<why alerts are disabled>"
  source: manual
```

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
feat(<domain>): add arrival SLA for <table_name>
```

PR description must include:

- Observed weekday histogram (from Trino).
- Producer cron and upstream dependencies consulted.
- Any inference caveats documented in `reason` fields.
- Note: **no behavior change until merged**; missing SLA file = alert on empty (default).

`CODEOWNERS` routes review to the domain team (e.g. `dags/people/**` →
`@quintoandar/enterprise-engineering`).

---

## Rollout guidance

1. Start with the **noisiest** tables (most empty-partition alerts in GChat).
2. Prefer **small PRs** (one DAG or ≤10 tables) for faster review via `CODEOWNERS`.
3. Do **not** set `mute: true` unless the domain explicitly requests full suppression.

---

## Out of scope

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
