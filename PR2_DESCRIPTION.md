# PR-2 — Branch: `chore/migrate-enrich-house-feature-inference-to-3p-supply`

## Suggested PR title

`chore(growth): migrate enrich_house_feature_inference to datalake_3p_supply.lead_3p`

## Suggested labels

`migration`, `enrich`, `growth`

---

## PR body

### Why?
* Migrate `enrich_house_feature_inference` away from the legacy `datalake_brokers_supply_processor.lead_3p` (enrich) table so the upstream DAG `enrich_brokers_supply_processor` can be deprecated. This DAG infers house features from `house_description` text via regex, so it depends on the new `house_description` column being exposed in `enrich_3p_supply.lead_3p` (delivered in PR-0).

### What?
* Updates `load_description_features.py` (Spark job) to read from `datalake_3p_supply.lead_3p` instead of the legacy enrich table; `house_description` and `uuid_lead` keep the same name, so only the source database needs to change.
* Reapoints the `house_description` lineage in `description_features.yml` to `datalake_3p_supply.lead_3p.house_description`.
* Updates `manual_modifications.yaml` to replace the `add` entry for `enrich_brokers_supply_processor:load-enrich-lead-3p` with the equivalent `enrich_3p_supply:load-enrich-lead-3p` first-run-of-day enforcement.
* Regenerates `dags/dependencies.yaml` so `enrich_house_feature_inference` now depends on `enrich_3p_supply` instead of `enrich_brokers_supply_processor`.

### How everything was tested?
* **Environment:** Local + Forno Airflow
* **Validation Details:**
    * **Forno Airflow:** ran `enrich_house_feature_inference` after PR-0 in forno; confirmed the inferred boolean feature columns in `enrich.description_features` have the same null rate and value distribution as the previous prod run.
    * **Databricks/SQL:** spot-checked that the upstream `datalake_3p_supply.lead_3p.house_description` returns non-null values for the same `uuid_lead` set that the legacy enrich exposed.
    * **CI/CD & Checks:** `make validate-metadata-files-exist`, `make validate-metadata-files-content`, `make validate-lineage-consistency`, `make validate-dependency-file-correctness`, `make create-dag-files` all green. `databricks-emr-sql-lint` reports zero findings (the inline Spark SQL string in the Python job lints clean).

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
| 1 | `dags/growth/enrich_house_feature_inference/spark_jobs/load_description_features.py` | Edit line 82 (source DB swap) |
| 2 | `dags/growth/enrich_house_feature_inference/metadata/enrich/description_features.yml` | Edit lineage on line 15 |
| 3 | `dags/dependency_exceptions/manual_modifications.yaml` | Replace `enrich_brokers_supply_processor` entry with `enrich_3p_supply` (lines 566-570) |
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

* **Depends on PR-0 being merged to prod.** PR-0 adds `house_description` to `enrich_3p_supply.lead_3p`, which is the column this DAG reads.
