# Exodus validation playbook — `reverse_reports`

Tier 1–3 validation for notebook migrations. **Runtime: Databricks prod only** (`quintoandar_prod`). Do not use Trino.

## Tiers

| Tier | Check | Pass criterion |
| --- | --- | --- |
| **1** | Row count | `legacy_count = migrated_count` (or signed-off delta documented) |
| **2** | Set diff | `EXCEPT` both ways on business columns = 0 (or signed-off) |
| **3** | Sample | Inspect up to 5 rows in `legacy EXCEPT migrated`; explain each |

Compare **legacy notebook SQL** (`dw_employee.*`) against **migrated** `queries/reverse/{table}.sql` (DW 2.0 sources). Drop partition columns (`year`, `month`, `day`) from diffs.

## Databricks CLI (mandatory for agents)

Follow [People domain — Databricks CLI](../../.cursor/rules/people/people_domain.mdc):

1. Pick a **RUNNING** People test cluster (`0119-124615-zurgst68` or `1107-173945-rr76o3kf`).
2. Prefix SQL with `USE CATALOG quintoandar_prod;`.
3. Unset conflicting token env vars: `env -u DATABRICKS_TOKEN -u DATABRICKS_HOST -u DATABRICKS_USERNAME databricks … -p PROD`.

### Helper scripts (per ticket)

Save under `.cursor/temp/{JIRA_KEY}/{branch-slug}/validation/`:

| Script | Purpose |
| --- | --- |
| `databricks_sql_runner.py` | Run one SQL statement; print result table |
| `run_reports_dw_validation.py` | Batch Tier 1–3 for `reports_dw` exports (DBP-1333 template) |

```bash
# Single query
uv run --script .cursor/temp/DBP-1333/master/validation/databricks_sql_runner.py \
  "SELECT COUNT(*) FROM dw_organization.dim_cost_center"

# Full reports_dw batch (after editing CASES / SQL paths)
uv run --script .cursor/temp/DBP-1333/master/validation/run_reports_dw_validation.py
```

Outputs: `validation_report.md`, `validation_results.json` in the same folder.

## Known remap deltas (DBP-1333)

| Export | Tier-1 note | Tier-2 / sign-off |
| --- | --- | --- |
| `cost_center_mapping_pin` | Count match | HC / HRBP drift vs legacy — People Systems sign-off |
| `pin_current_employee_snapshot`, `pin_systems_employee_roster` | Primary assignment grain (`is_primary_assignment_for_snapshot`); ~10,984 rows with `is_current` (2026-06-25) | Grain remap vs legacy `fact_employees` / all-assignments `fas.is_current`; document Δ in PR |
| `pin_cost_center_roster` | Primary assignment grain; row count aligns with `employee_snapshots` current primary | Grain remap vs legacy all-assignments export; document Δ in PR |
| `leiturinha_holder_roster` | **2,598 = 2,598** (2026-06-25) vs legacy `dw_employee.fact_employees` | Core cols 0 diffs. `residencia_*` with `TRIM`: **15** symmetric diffs (254 without TRIM). Address upstream fix: [#25191](https://github.com/quintoandar/bi-etl-ejuice/pull/25191) / [DBP-1550](https://quintoandar.atlassian.net/browse/DBP-1550). Residual: legacy `contact.address` vs `address_street` nulls — Benefits sign-off. |

### Tier 2 — exclude load-time stamps

Do not fail Tier 2 on `ts_load`, `NOW()` / `CURRENT_TIMESTAMP()`, or dates derived only from load `ts_load` (e.g. `dt_last_update`). See skill `add-people-reverse-reports-export` / `reference.md`.

### Tier 2 — normalize legacy address whitespace

For Leiturinha (and similar legacy `dim_employee_contact` exports), apply `TRIM()` on `residencia_*` columns in both legacy and migrated sides before `EXCEPT`. Legacy `contact.address` often has trailing spaces; without `TRIM`, Tier 2 inflates (~254 false positives on 2026-06-25 run).

## Sign-off

Reply **validation OK** in the skill thread with `validation_report.md` summary or paste Tier 1–3 table before Forno / PR.
