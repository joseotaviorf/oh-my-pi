# Cluster validation DAGs

Opt-in smoke tests on Graviton consolidation cluster presets before changing prod `cluster.type`.

## Enable

Add a `validation` block to `{dag}_cluster.yml` (merged into the declaration at compile time). Presence of `validation.cluster` opts the DAG in.

Prod `cluster:` is copied verbatim from the declaration (or kept as-is when already split). Validation is generated from **effective prod topology**, not from prod preset name alone.

```yaml
cluster:
  type: databricks_16_4_med_general_cluster

validation:
  cluster:
    type: consolidation_s_general_cluster
    custom_configurations:
      num_workers: 3
      node_type_id: m6g.xlarge
```

### How validation presets are chosen

1. Resolve effective prod with `merge_cluster_configuration` (same as runtime `JobClusterEngine`).
2. Map worker and driver `node_type_id` to Graviton (`m5`/`m5a`/`m-fleet` → `m6g`, `r*` → `r6g`, `c*` → `c6g`; size suffix preserved).
3. **Single-node alignment:** prod single-node → validation `consolidation_*_single_node_*` only; prod multi-node → multi-node consolidation only (never flip modes).
4. **Worker-first preset match:** pick a consolidation preset whose default `node_type_id` equals the mapped worker type.
5. **Homogeneous driver/worker** (same instance size): preset must also match `driver_node_type_id`; overrides are only for non-default fields (`spark_version`, `num_workers`, etc.).
6. **Heterogeneous driver/worker:** match on worker size only; override `driver_node_type_id` when it differs from the preset default (do not copy worker overrides from driver).
7. Emit `validation.cluster.custom_configurations` only when effective prod differs from the validation preset defaults.
8. **`aws_attributes` overrides:** when effective prod `aws_attributes` differ from the matched consolidation preset (e.g. `instance_profile_arn` from legacy `databricks_16_4_*_people_cluster` presets, or `ebs_volume_size`, `first_on_demand`, `availability`), emit the full key-level diff under `validation.cluster.custom_configurations.aws_attributes`.

**Skip validation** when prod is already the sole consolidation preset that matches the topology (e.g. prod `consolidation_m_memory_cluster` with `r6g.2xlarge` worker and driver). The generator omits the `validation:` block entirely.

When validation is emitted, `validation.cluster.type` must still differ from prod `cluster.type` (enforced by `DAGDeclarationValidator`).

### Generator and CI

```bash
# Regenerate under a subtree (optional SOURCE_REF when cluster: was removed from declarations)
make extract-cluster-validation-files DAG_PATH=dags/platform/ SOURCE_REF=<pre-split-git-ref>

# CI: fail if on-disk *_cluster.yml differs from generator output
make validate-cluster-validation-files
```

Keep `spark.databricks.sql.initial.catalog.namespace` Jinja on a single line in `*_cluster.yml` (no PyYAML line folding). `validate-cluster-validation-files` rejects folded `quintoandar_{{ var.value.environment }}` values.

Implementation: `packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/extract_cluster_validation_files.py` and `cluster_validation_mapping.py`.

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
