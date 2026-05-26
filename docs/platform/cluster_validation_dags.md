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

Phase 1: `query_delta`, `query`, `query_view`, `dw_query`, `metric_query` without unsupported `load_spark_job` (unless opted in).

Phase 2: CDC clean layer, gsheets, database_pull, API ingestion, reverse, qube (via task groups).

## UC grants

Job clusters need write access to schema `cluster_validation` in `quintoandar_prod` (one-time platform grant).
