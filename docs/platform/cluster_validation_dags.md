# Cluster validation DAGs

Opt-in smoke tests on Graviton consolidation cluster presets before changing prod `cluster.type`.

## Enable

Add a `validation` block to the DAG declaration or cluster file (presence of `validation.cluster` opts in):

```yaml
cluster:
  type: databricks_16_4_med_general_cluster

validation:
  cluster:
    type: consolidation_s_general_single_node_cluster
```

Rules enforced by `DAGDeclarationValidator`:

- `validation.cluster.type` must start with `consolidation_`
- Must differ from prod `cluster.type`
- DAGs with `load_spark_job` need `validation.allow_custom_spark_job: true`

## Generated Airflow DAG

The compiler emits a second DAG: `bietlejuice.{dag_name}__validation`

- `schedule`: manual only (`null`)
- No `dependencies.yaml` dataset wiring
- Load tasks do not publish datasets (`produce_datasets=false`)
- Cluster preset from `validation.cluster`
- Airflow tag: `cluster_validation`

## Write target naming

| Prod | Validation (UC) |
|------|-----------------|
| `datalake_{schema}.{table}` | `cluster_validation.datalake_{schema}___{table}` |
| `dw_{schema}.{table}` | `cluster_validation.dw_{schema}___{table}` |
| `metric_{schema}.{table}` | `cluster_validation.metric_{schema}___{table}` |
| `qube_dimensions.{table}` | `cluster_validation.qube_dimensions___{table}` |
| `qube_measures.{table}` | `cluster_validation.qube_measures___{table}` |
| `qube_metrics.{table}` | `cluster_validation.qube_metrics___{table}` |

SQL reads stay on prod-qualified sources. Phase 1 does not rewrite `inner_dependencies`.

S3 path: `s3a://{datalake_bucket}/validation/cluster_validation/{prod_database}/`

## Runbook

1. Merge declaration + regenerated `*_dag.py`
2. Trigger `bietlejuice.{dag}__validation` manually (use `test_run` conf if needed)
3. Confirm rows in `cluster_validation.*___*` tables and prod tables unchanged
4. Switch prod `cluster.type` to consolidation when satisfied; remove `validation` block

## Eligibility

```bash
python scripts/list_cluster_validation_eligible_dags.py
```

Phase 1: `query_delta`, `query`, `dw_query`, `metric_query` without unsupported `load_spark_job` (unless opted in).

Phase 2 (implemented, PR2–PR5): `cdc`, `dms_cdc`, `gsheets`, `database_pull`, `api_ingestion`, `reverse`, `core_model`, `qube_dimension`, `qube_measure`, `qube_metric`.

Phase 2 (excluded / future work): `wonka`, `query_view` — see [Exclusions](#exclusions) below.

## Exclusions

### wonka

`load_wonka` is a pipeline runner that dispatches to other jobs at runtime. It cannot redirect table output without changes to the Wonka runner itself. `cluster_validation` DAGs for `wonka` workflow types are currently **not supported** — the validator will raise if `validation:` is set on a wonka DAG.

### query_view

`query_view` creates Trino/Spark views only; it does not materialise any table. There are no write-target rows to redirect, and no `cluster_validation` tables are emitted. View creation on a validation cluster is harmless but does not test compute behaviour, so `query_view` is **excluded** from Phase 2 write-target wiring (future work if view DDL compatibility testing is needed).

## UC grants

Job clusters need write access to schema `cluster_validation` in `quintoandar_prod` (one-time platform grant).
