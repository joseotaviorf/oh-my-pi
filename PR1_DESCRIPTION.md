# PR-1 — Branch: `chore/migrate-enrich-kodak-to-3p-supply`

## Suggested PR title

`chore(kodak): migrate enrich_kodak from legacy lead_3p to datalake_3p_supply.lead_3p`

## Suggested labels

`migration`, `enrich`, `3p-partners`

---

## PR body

### Why?
* Migrate `enrich_kodak` away from the legacy `datalake_brokers_supply_processor.lead_3p` (enrich) table so the upstream DAG `enrich_brokers_supply_processor` can be deprecated. The new source `datalake_3p_supply.lead_3p` already provides all the columns this DAG reads (`uuid_lead`, `id_lead_3p`).

### What?
* Updates `image_inspection_amenities.sql` to read from `datalake_3p_supply.lead_3p` and adopts the new primary-key column name (`id_lead_3p` replaces `id AS id_lead_3p`).
* Reapoints the `id_lead_3p` lineage in `image_inspection_amenities.yml` to `datalake_3p_supply.lead_3p.id_lead_3p`.
* Updates the `dag_purpose` documentation in `enrich_kodak_declaration.yml` to reference the new source table.
* Regenerates `dags/dependencies.yaml` so `enrich_kodak` now depends on `enrich_3p_supply` instead of `enrich_brokers_supply_processor`.

### How everything was tested?
* **Environment:** Local + Forno Airflow
* **Validation Details:**
    * **Forno Airflow:** ran `enrich_kodak` end-to-end after PR-0 was already in forno; confirmed `image_inspection_amenities` produces a row count and `id_lead_3p` distribution consistent with the previous prod run.
    * **Databricks/SQL:** spot-checked `SELECT COUNT(*) FROM datalake_kodak.image_inspection_amenities` and `SELECT COUNT(DISTINCT id_lead_3p) FROM datalake_kodak.image_inspection_amenities` against the previous run; no regression.
    * **CI/CD & Checks:** `make validate-metadata-files-exist`, `make validate-metadata-files-content`, `make validate-lineage-consistency`, `make validate-dependency-file-correctness`, `make create-dag-files` all green. `databricks-emr-sql-lint` reports zero findings.

#### Screenshots
* *To do (author): Add screenshots for UI or dashboard changes; for data/backend-only PRs, replace this line with `Not applicable` or remove it.*

### Checklist before opening the PR!
- [ ] My code follows the style guidelines and [name conventions](https://docs.google.com/document/d/1mPPA716eoT3EZSqY0gA8a9ao4ObMyI9Y8QNd7CzlWWY) for DAGs, databases, columns, etc.
- [ ] I have made corresponding changes to the documentation;
- [ ] I have added tests that prove my fix is effective or that my feature works.

---

## Files to change in this branch (reference)

| # | Path | Action |
|---|---|---|
| 1 | `dags/3p_partners/enrich_kodak/queries/enrich/image_inspection_amenities.sql` | Edit lines 7 and 15 (column rename and source table swap) |
| 2 | `dags/3p_partners/enrich_kodak/metadata/enrich/image_inspection_amenities.yml` | Edit lineage on line 16 |
| 3 | `dags/3p_partners/enrich_kodak/enrich_kodak_declaration.yml` | Edit `dag_purpose` text on line 24 |
| 4 | `dags/dependencies.yaml` | Regenerated via `make dependencies-file` |

## Pre-merge commands

```bash
make validate-metadata-files-exist
make validate-metadata-files-content
make validate-lineage-consistency
make dependencies-file && git add dags/dependencies.yaml
make validate-dependency-file-correctness
make create-dag-files
```

## Dependencies between PRs

* **Depends on PR-0 being merged to prod.** PR-0 adds the columns this DAG already needs (only `id_lead_3p` rename is consumed here — already present in the current `enrich_3p_supply.lead_3p`).
