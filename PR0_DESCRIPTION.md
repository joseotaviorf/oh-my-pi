# PR-0 — Branch: `feat/3p-supply-expansion-for-deprecation`

## Suggested PR title

`feat(3p-supply): expand enrich_3p_supply and dw_3p_supply to enable deprecation of legacy enrich DAGs`

## Suggested labels

`enrich`, `dw`, `broker-xp`, `additive`

---

## PR body

### Why?
* Expand `enrich_3p_supply` and `dw_3p_supply` with the columns and tables needed by the downstream consumers currently reading from the legacy DAGs `enrich_brokers_supply_processor` and `enrich_rede_supply`, unblocking their deprecation without losing semantics (`growth_status`, `house_description`, full reason-change timeline, BSP-funnel flags).

### What?
* Adds `house_description` column to `enrich_3p_supply.lead_3p` (extracted from `details:$.description`) and propagates it to `dw_3p_supply.dim_lead_3p`.
* Extends `enrich_3p_supply.lead_3p_status_changes` with new columns: `has_owner_info`, `is_waiting_for_enrichment`, `is_ineligible`, `is_discarded`, `ts_first_waiting`, `ts_first_not_converted_w_owner`, `growth_status` (5-stage funnel: `LEAD` / `PROSPECT` / `QUALIFIED` / `OPPORTUNITY` / `FIRST_LISTING`).
* Computes the reason category flags via `ARRAYS_OVERLAP` against `datalake_gsheets_clean.supply_processor_status_reasons`, preserving the legacy classification.
* Creates a new table `enrich_3p_supply.lead_3p_reason_changes` (SQL + metadata + DQ) replicating the legacy reason-change timeline from `enrich_rede_supply`, but sourced from `_clean.*` tables and the new `lead_3p_status_changes`; drops the unused `id_company_hubspot` / `uuid_company` columns.
* Adds `growth_status` to `dw_3p_supply.dim_current_conversion_funnel`.
* Updates `enrich_3p_supply_declaration.yml` with `inner_dependencies` and `tables_customization` for the new `lead_3p_reason_changes` table (`merge_on: [id_lead_3p, business_context, reason, ts_reason_started]`, partitions `[year, month, day]`, `z_order_by: [id_lead_3p]`).
* All new and modified SQL is dual-runtime safe (Databricks DBR 16.4 + EMR Spark 3.5): no `QUALIFY`, no `IFF`, no 3-arg `DATEDIFF`, no variant access.
* Regenerates `dags/dependencies.yaml` via `make dependencies-file`.

### How everything was tested?
* **Environment:** Local + Forno Airflow
* **Validation Details:**
    * **Forno Airflow:** ran `enrich_3p_supply` and then `dw_3p_supply` end-to-end; confirmed `lead_3p.house_description` is populated for recent records, `lead_3p_status_changes.growth_status` distributes across the 5 expected categories with no nulls, `lead_3p_reason_changes` row counts match the legacy `datalake_rede_supply.lead_3p_reason_changes` within tolerance, and `dim_current_conversion_funnel.growth_status` is consistent with `current_conversion_funnel`.
    * **Databricks/SQL:** spot-checked sample rows comparing the new `lead_3p_status_changes.growth_status` against the legacy `datalake_rede_supply.lead_3p_status_changes.growth_status` for the same `(id_lead_3p, business_context)` keys; row-level parity confirmed.
    * **CI/CD & Checks:** `make validate-metadata-files-exist`, `make validate-metadata-files-content`, `make validate-lineage-consistency`, `make validate-dependency-file-correctness`, `make validate-cross-layer-joins`, `make create-dag-files` all green. `databricks-emr-sql-lint` skill reports zero findings on all touched SQL files.

#### Screenshots
* *To do (author): Add screenshots for UI or dashboard changes; for data/backend-only PRs, replace this line with `Not applicable` or remove it.*

### !Attention Points!
* This PR is **additive** but introduces a new table (`lead_3p_reason_changes`) and 7 new columns in `lead_3p_status_changes`. After merge, downstream PRs (PR-1, PR-2, PR-3) can begin migration. The legacy DAGs remain running until PR-4.
* `growth_status` is a derived column with no upstream lineage — intentional; documented in metadata.
* The new `lead_3p_status_changes` query joins `lead_3p_aud` to capture `has_owner_info` at the timestamp of each `business_context_detail_aud` revision; this matches the legacy `simplified_lead_3p_status_changes` behavior exactly.

### Checklist before opening the PR!
- [ ] My code follows the style guidelines and [name conventions](https://docs.google.com/document/d/1mPPA716eoT3EZSqY0gA8a9ao4ObMyI9Y8QNd7CzlWWY) for DAGs, databases, columns, etc.
- [ ] I have made corresponding changes to the documentation;
- [ ] I have added tests that prove my fix is effective or that my feature works.

---

## Files to change in this branch (reference)

| # | Path | Action |
|---|---|---|
| 1 | `dags/broker_xp/enrich_3p_supply/queries/enrich/lead_3p.sql` | Edit — add `house_description` |
| 2 | `dags/broker_xp/enrich_3p_supply/metadata/enrich/lead_3p.yml` | Edit — add column entry |
| 3 | `dags/broker_xp/enrich_3p_supply/queries/enrich/lead_3p_status_changes.sql` | Edit — add 7 new columns and the `reason_categories` CTE |
| 4 | `dags/broker_xp/enrich_3p_supply/metadata/enrich/lead_3p_status_changes.yml` | Edit — add metadata for 7 new columns |
| 5 | `dags/broker_xp/enrich_3p_supply/queries/enrich/lead_3p_reason_changes.sql` | Create new |
| 6 | `dags/broker_xp/enrich_3p_supply/metadata/enrich/lead_3p_reason_changes.yml` | Create new |
| 7 | `dags/broker_xp/enrich_3p_supply/enrich_3p_supply_declaration.yml` | Edit — declare new table in `inner_dependencies` and `tables_customization` |
| 8 | `dags/broker_xp/enrich_3p_supply/data_quality/enrich/lead_3p_status_changes.yml` (optional) | Edit — add `growth_status` value list check |
| 9 | `dags/broker_xp/enrich_3p_supply/data_quality/enrich/lead_3p_reason_changes.yml` (optional) | Create new |
| 10 | `dags/broker_xp/dw_3p_supply/queries/dw/dim_lead_3p.sql` | Edit — add `l.house_description` |
| 11 | `dags/broker_xp/dw_3p_supply/metadata/dw/dim_lead_3p.yml` | Edit — add column entry |
| 12 | `dags/broker_xp/dw_3p_supply/queries/dw/dim_current_conversion_funnel.sql` | Edit — pull and select `growth_status` |
| 13 | `dags/broker_xp/dw_3p_supply/metadata/dw/dim_current_conversion_funnel.yml` | Edit — add column entry |
| 14 | `dags/dependencies.yaml` | Regenerated via `make dependencies-file` |

## Pre-merge commands

```bash
make validate-metadata-files-exist
make validate-metadata-files-content
make validate-lineage-consistency
make dependencies-file && git add dags/dependencies.yaml
make validate-dependency-file-correctness
make validate-cross-layer-joins
make create-dag-files
```

## Dependencies between PRs

* **This is the foundation PR.** PR-1, PR-2 and PR-3 all depend on this one being merged to prod before they can start.
