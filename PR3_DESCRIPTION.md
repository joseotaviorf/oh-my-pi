# PR-3 — Branch: `chore/migrate-enrich-supply-acquisition-to-3p-supply`

## Suggested PR title

`chore(growth): migrate enrich_supply_acquisition to datalake_3p_supply`

## Suggested labels

`migration`, `enrich`, `growth`

---

## PR body

### Why?
* Migrate the last two consumer queries inside `enrich_supply_acquisition` away from the legacy enrich layers (`datalake_brokers_supply_processor.lead_3p`, `datalake_rede_supply.lead_3p_status_changes`, `datalake_rede_supply.lead_3p_reason_changes`) and onto the equivalent tables in `datalake_3p_supply`, unblocking the deprecation of `enrich_brokers_supply_processor` and `enrich_rede_supply`. All semantics — `growth_status` funnel stages and the reason-change timeline — are preserved because PR-0 extended the new enrich layer with the missing columns and the new `lead_3p_reason_changes` table.

### What?
* `conversion_lookup.sql`: swap `datalake_brokers_supply_processor.lead_3p` for `datalake_3p_supply.lead_3p`; adopt the new column names (`id_lead_3p` instead of `id`, `ts_lead_created` instead of `ts_created`); update the `ROW_NUMBER()` partition key accordingly.
* `landing_3p.sql`: swap both legacy source tables for the new ones in `datalake_3p_supply`; adopt the new column names (`ts_start` instead of `ts_status_started`, `region_id` instead of `id_region`, `id_lead_3p` instead of `id` for the lead join). The pivot/unpivot business logic over `growth_status` is unchanged because `growth_status` is now a first-class column of `datalake_3p_supply.lead_3p_status_changes` and `growth_status_when_reason_started` is a first-class column of `datalake_3p_supply.lead_3p_reason_changes`.
* `conversion_lookup.yml` and `landing_3p.yml`: reapoint all `lineage:` entries to the corresponding columns in `datalake_3p_supply.*`.
* Regenerates `dags/dependencies.yaml` so `enrich_supply_acquisition` now depends on `enrich_3p_supply` instead of `enrich_brokers_supply_processor` and `enrich_rede_supply`.

### How everything was tested?
* **Environment:** Local + Forno Airflow
* **Validation Details:**
    * **Forno Airflow:** ran `enrich_supply_acquisition` end-to-end after PR-0 was in forno; confirmed `landing_3p` and `conversion_lookup` produce row counts and `growth_status` / `business_context` distributions consistent with the previous prod run.
    * **Databricks/SQL:** for a sample of `(id_lead_3p, business_context)` keys, joined the new and legacy `landing_3p` outputs and verified that `growth_status`, `status`, `reason`, `reason_type` and `ts_event` match.
    * **CI/CD & Checks:** `make validate-metadata-files-exist`, `make validate-metadata-files-content`, `make validate-lineage-consistency`, `make validate-dependency-file-correctness`, `make validate-cross-layer-joins`, `make create-dag-files` all green. `databricks-emr-sql-lint` reports zero new findings on the modified SQL.

#### Screenshots
* *To do (author): Add screenshots for UI or dashboard changes; for data/backend-only PRs, replace this line with `Not applicable` or remove it.*

### !Attention Points!
* `landing_3p.sql` keeps `QUALIFY` clauses (already present in the file in production); confirm the DAG is still Databricks-only or, if dual-runtime is required, rewrite the affected `QUALIFY` blocks as `ROW_NUMBER() ... WHERE rn = 1`. The `databricks-emr-sql-lint` skill output should be used as the source of truth.
* The pivoted `growth_status` values must continue to map to the 5 funnel stages (`LEAD`, `PROSPECT`, `QUALIFIED`, `OPPORTUNITY`, `FIRST_LISTING`); any new `growth_status` value introduced by PR-0 would surface as an unmapped row in the pivot CTE.

### Checklist before opening the PR!
- [ ] My code follows the style guidelines and [name conventions](https://docs.google.com/document/d/1mPPA716eoT3EZSqY0gA8a9ao4ObMyI9Y8QNd7CzlWWY) for DAGs, databases, columns, etc.
- [ ] I have made corresponding changes to the documentation;
- [ ] I have added tests that prove my fix is effective or that my feature works.

---

## Files to change in this branch (reference)

| # | Path | Action |
|---|---|---|
| 1 | `dags/growth/enrich_supply_acquisition/queries/enrich/conversion_lookup.sql` | Edit `lead_conversion_3p` CTE (lines 107-125): source table, column renames, partition key |
| 2 | `dags/growth/enrich_supply_acquisition/queries/enrich/landing_3p.sql` | Edit `tb_aux` and `discards` CTEs (lines 1-28): source tables, column renames |
| 3 | `dags/growth/enrich_supply_acquisition/metadata/enrich/conversion_lookup.yml` | Edit lineages on lines 20 and 51 |
| 4 | `dags/growth/enrich_supply_acquisition/metadata/enrich/landing_3p.yml` | Edit 9 lineages |
| 5 | `dags/dependencies.yaml` | Regenerated via `make dependencies-file` |

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

* **Depends on PR-0 being merged to prod.** PR-0 adds `growth_status` to `datalake_3p_supply.lead_3p_status_changes` and creates the new `datalake_3p_supply.lead_3p_reason_changes` table — both required by `landing_3p.sql`.
