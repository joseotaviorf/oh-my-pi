# PR-4 — Branch: `chore/deprecate-enrich-rede-supply-and-enrich-brokers-supply-processor`

## Suggested PR title

`chore(3p-partners): deprecate enrich_brokers_supply_processor and enrich_rede_supply`

## Suggested labels

`deprecation`, `cleanup`, `3p-partners`, `irreversible`

---

## PR body

### Why?
* Retire the legacy enrich DAGs `enrich_brokers_supply_processor` and `enrich_rede_supply` now that all in-repo downstream consumers (`enrich_kodak`, `enrich_house_feature_inference`, `enrich_supply_acquisition`) have been migrated to the equivalent tables in `datalake_3p_supply` (PRs 1, 2 and 3). External alignment with users and other teams was already confirmed before the migration started.

### What?
* Removes the entire `dags/3p_partners/enrich_brokers_supply_processor/` folder (declaration, dag file, queries and metadata for `lead_3p`, `business_context_detail`, `file`).
* Removes the entire `dags/3p_partners/enrich_rede_supply/` folder (declaration, dag file, queries and metadata for `simplified_lead_3p_status_changes`, `lead_3p_status_changes`, `lead_3p_status`, `lead_3p_reason_changes`, `lead_3p_reasons`, `file_sks`, `lead_3p_sks`, `listing_revisions`).
* Cleans up `dags/dependency_exceptions/manual_modifications.yaml`: removes the `bietlejuice.enrich_rede_supply:` and `bietlejuice.enrich_brokers_supply_processor:` blocks (the `enrich_house_feature_inference` reference was already swapped to `enrich_3p_supply` in PR-2).
* Regenerates `dags/dependencies.yaml` so the deprecated DAGs no longer appear as upstream nodes for any consumer.
* (Optional) Updates the TARS knowledge base in `plugins/tars/skills/tars/references/business_entities/broker_xp.md` and `docs/llm_context/business_entities/broker_xp.md` to reference `datalake_3p_supply.*` instead of the legacy databases.

### How everything was tested?
* **Environment:** Local + Forno Airflow
* **Validation Details:**
    * **Forno Airflow:** confirmed that after this branch is deployed to forno, the deprecated DAGs no longer appear in the Airflow UI and all migrated consumers (`enrich_kodak`, `enrich_house_feature_inference`, `enrich_supply_acquisition`) continue to schedule and complete successfully.
    * **CI/CD & Checks:** `make validate-metadata-files-exist`, `make validate-metadata-files-content`, `make validate-lineage-consistency`, `make validate-dependency-file-correctness`, `make validate-cross-layer-joins`, `make create-dag-files` all green. No SQL files modified — no `databricks-emr-sql-lint` run required.

#### Screenshots
* *To do (author): Add screenshots for UI or dashboard changes; for data/backend-only PRs, replace this line with `Not applicable` or remove it.*

### !Attention Points!
* **Irreversible.** Re-creating these DAGs after merge would require reverting this PR or rebuilding them from scratch. Make sure PRs 1, 2 and 3 are running cleanly in production before merging.
* **`dags/platform/sla_monitoring/prod_conf.yml` is intentionally NOT modified in this PR** (out of scope by request). After merge, lines 195 (`bietlejuice.enrich_brokers_supply_processor: 04:51`) and 325 (`bietlejuice.enrich_rede_supply: 05:38`) will reference non-existent DAGs and may emit runtime warnings from the `sla_monitoring` DAG. Whoever owns the SLA monitoring can clean those up in a follow-up.
* **Physical Delta cleanup is out of scope.** The legacy schemas `datalake_brokers_supply_processor` (enrich layer) and `datalake_rede_supply` will keep their Delta tables in S3 / Unity Catalog after this PR; manual drop in Databricks is recommended after a soft-retention window for historical rollback.

### Checklist before opening the PR!
- [ ] My code follows the style guidelines and [name conventions](https://docs.google.com/document/d/1mPPA716eoT3EZSqY0gA8a9ao4ObMyI9Y8QNd7CzlWWY) for DAGs, databases, columns, etc.
- [ ] I have made corresponding changes to the documentation;
- [ ] I have added tests that prove my fix is effective or that my feature works.

---

## Files / folders changed in this branch (reference)

| # | Path | Action |
|---|---|---|
| 1 | `dags/3p_partners/enrich_brokers_supply_processor/` | Remove entire folder |
| 2 | `dags/3p_partners/enrich_rede_supply/` | Remove entire folder |
| 3 | `dags/dependency_exceptions/manual_modifications.yaml` | Remove `bietlejuice.enrich_rede_supply:` block (lines 678-680) and `bietlejuice.enrich_brokers_supply_processor:` block (lines 1382-1384) |
| 4 | `dags/dependencies.yaml` | Regenerated via `make dependencies-file` |
| 5 | `plugins/tars/skills/tars/references/business_entities/broker_xp.md` (optional) | Edit references to legacy databases |
| 6 | `docs/llm_context/business_entities/broker_xp.md` (optional) | Edit references to legacy databases |
| 7 | `dags/platform/sla_monitoring/prod_conf.yml` | **NOT changed** — explicit out-of-scope per request |

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

* **Depends on PR-1, PR-2 and PR-3 all being merged to prod and running cleanly for at least one successful schedule.** This PR removes the DAGs whose outputs are no longer read by anything in the repo.
