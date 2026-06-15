# Wonka cluster validation — Forno pilot runbook

Manual verification checklist after merging bi-etl-ejuice and QuintoML worktree branches.

## Prerequisites

- UC grant on `cluster_validation` schema for the Forno service principal (see `cluster_validation_dags.md`).
- Both repos deployed to Forno from `feat/wonka-cluster-validation` (or successor PR branches).

## Pilot DAGs

| Production DAG | Validation DAG |
|----------------|----------------|
| `quintoml.wonka.user_visits` | `quintoml.wonka.user_visits__validation` |
| `quintoml.wonka.house_main` | `quintoml.wonka.house_main__validation` |

## Steps (per DAG)

1. Confirm both DAGs appear in Forno Airflow UI.
2. Trigger `quintoml.wonka.<name>__validation` manually (do not trigger prod).
3. In Databricks run logs, verify:
   - Cluster uses `consolidation_*` instance types (Graviton).
   - Init scripts: `configure_spark.sh`, `install_pex_generic.sh`, `get_credentials_from_vault.sh`.
   - `load-wonka-*` task succeeds.
4. In Unity Catalog / Trino, verify rows in:
   - `cluster_validation.wonka___<feature_set>`
   - `cluster_validation.wonka___<feature_set>__latest` (when Datazord enabled in prod)
5. Confirm prod tables unchanged: `wonka.<feature_set>`, `wonka.<feature_set>__latest`.
6. Confirm no CDF Kafka traffic from validation run (task `load-cdf-to-datazord` must not exist on validation DAG).

## Rollback

Remove `validation:` block from pilot `prod.yml` files and redeploy QuintoML; bi-etl-ejuice redirect code is inert without validation DAGs.
