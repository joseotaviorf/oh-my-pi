# EMR DAG observability

Bring Databricks-parity cost and utilization visibility to Airflow-orchestrated
EMR DAGs from this repo (`emr_cluster_base`, tag `provisioner: emr`). For fleet **managed scaling** (`max_nodes` on `core_nodes` / `task_nodes`), see [emr_fleet_autoscaling.md](emr_fleet_autoscaling.md).

- **Status:** In progress (stacked PRs Phases 0–4)
- **Related code:** `dags/platform/enrich_emr_health/`, `dags/platform/dw_emr_health/`,
  `dags/platform/metric_observability__dags/queries/metric/dag_health.sql`,
  `local/emr_monitor/{metrics,pricing,logs}.py`
- **Explicit v1 omissions:** do **not** restore `spark.eventLog.dir` on
  `emr_cluster_base`; do **not** unpause `bietlejuice.enrich_spark_event_logs`.
  Spark stage KPIs stay NULL / uncovered for EMR rows.

## Why

`fact_databricks_task_run` filters `provisioner IN ('bietlejuice','wonka','quintoml')`.
EMR clusters tag `provisioner: emr`, so migrated DAGs drop out of
`dag_health`. Operators cannot see which EMR DAGs ran, estimated compute cost,
or CPU/memory pressure the way they can on Databricks.

## Metric mapping (have vs need)

| Metric family | Databricks today | EMR source of truth (v1) | AWS / repo refs | Gap / decision |
|---|---|---|---|---|
| DAG/task identity | Lakeflow job/task timelines | EventBridge `EMR Cluster State Change` events (`datalake_emr_events_clean.events`) carry exact cluster name `{dag_id}_{run_id}` (primary >= 2026-08-28); pre-event fallback uses CUR hour-bucket heuristic against `datalake_airflow.task_instance` | EventBridge / CUR / Airflow; `packages/bietlejuice-core/.../prod_conf.yml` `emr_cluster_base` | Build spine + facts |
| Cost (compute estimate) | DBU + calculated EC2 from `node_timeline` | Instance fleet/group timeline (EMR `list_instances` + EC2) × on-demand/spot from `datalake_databricks_pricing.dim_ec2_price`; EBS gb-month × hours; port `local/emr_monitor/pricing.py` `estimate_cluster_cost` | EC2 Pricing / `dim_ec2_price`; emr_monitor pricing | Build `daily_emr_cluster_health` |
| Cost (billed truth) | `system.billing.usage` | CUR + cost allocation tags (`cost-center`, `dag_id`, `provisioner`) — **after v1** | [Cost Explorer + EMR tags](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/create-detailed-cost-and-usage-reports-for-amazon-emr-clusters-by-using-aws-cost-explorer.html) | Not v1 |
| CPU | `daily_cluster_health` P50/P95 from `node_timeline` | CloudWatch `AWS/EC2` `CPUUtilization` per instance → cluster-day P50/P95 (MASTER=driver, CORE/TASK=workers). Prototype: `local/emr_monitor/metrics.py` `EC2_INSTANCE_METRICS` | [EMR CloudWatch metrics](https://docs.aws.amazon.com/emr/latest/ManagementGuide/UsingEMR_ViewingMetrics.html) | CW ~2 week retention — ETL daily |
| Memory | driver/worker mem % from `node_timeline` | CloudWatch `AWS/ElasticMapReduce`: `MemoryTotalMB`, `MemoryAllocatedMB`, `MemoryAvailableMB`, `YARNMemoryAvailablePercentage` → used%. Prototype: `EMR_CLUSTER_METRICS` | Same EMR CW guide | Cluster-level YARN memory only in v1 |
| Disk / network | NVMe / node disk from Databricks system tables | CloudWatch `AWS/EC2` `EBSReadBytes`/`EBSWriteBytes` (+ terminated aliases) + `AWS/EBS` volume metrics; `NetworkIn`/`NetworkOut`. Prototype: `EBS_VOLUME_METRICS`, `TERMINATED_EBS_EC2_METRICS` | EMR / EC2 / EBS CW docs | Daily pull; no Photon NVMe analogue |
| Spark stage stats | `spark_stage_metrics` ← event logs → fact join | **Deferred in v1.** No writer-conf restore; no `enrich_spark_event_logs` unpause. Stage-backed fact columns stay NULL for EMR | Parser knows `s3://5a-databricks/spark-event-logs-emr/<dag_id>/` but warehouse last load **2026-05-20**; #26210 removed writer `eventLog.dir` | Intentional v1 omission |

EMR step / node / container logs under
`s3://…/emr/logs/dags/<dag_id>/<j-…>/` are operational text only — they do
**not** contain billed USD. Actual invoice cost lives in Cost Explorer / CUR
(after v1).

## Spine

```text
EMR API + CloudWatch (+ Airflow enrich_airflow)
        │
        ▼
daily_emr_cluster_health   +   emr_dag_task_spine
        │                              │
        └──────────────┬───────────────┘
                       ▼
              fact_emr_task_run
                       ▼
              fact_emr_dag_run
                       ▼
         dag_health  (UNION Databricks + EMR)
```

Preferred schema: `datalake_emr_health` / `dw_emr_health`. Contingency: `emr_`
tables under `datalake_databricks_health` / `dw_databricks_health` if platform
conventions block a new schema — still keep **separate** fact SQL from
Databricks facts.

Spark event-log ingest / `spark_stage_metrics` are **out of v1** (no
`spark.eventLog.dir` restore on `emr_cluster_base`; `enrich_spark_event_logs`
stays paused).

## Where EMR can exceed Databricks

- **1:1 cluster-per-run cost attribution** — `cluster_name={{ dag.dag_id }}_{{ run_id }}`
  makes estimated EC2+EBS map cleanly to a logical Airflow run (harder on
  multi-job Databricks shared clusters).
- **Native CloudWatch YARN** — `ContainerAllocated` / `ContainerPending`,
  `YARNMemoryAvailablePercentage` without scraping Spark UIs.
- **LogUri locality** — step/node/container logs under a predictable S3 prefix
  per DAG/cluster for debugging (still not a cost source).

## Alternatives (locked for v1)

| Topic | Chosen | Deferred |
|---|---|---|
| Cost | Calculated EC2+EBS via `dim_ec2_price` + emr_monitor formulas | CUR / Cost Explorer billed truth |
| Utilization | CloudWatch YARN + EC2 CPU/disk/network | Spark executor / stage metrics from event logs |
| Airflow↔EMR bridge | EventBridge events (primary >= 2026-08-28) + CUR hour-bucket heuristic (pre-event fallback) | XCom export (only if match rate &lt;90%) |
| Product surface | Parallel `fact_emr_*` then UNION into `dag_health` | Separate `emr_dag_health` metric table; overloading `fact_databricks_*` |

## Phased delivery (one Graphite PR per phase)

| Stack order | Phase | PR title stem | Delivers |
|---|---|---|---|
| 1 (bottom) | 0 | `docs(platform): EMR observability mapping` | This document |
| 2 | 1 | `feat(emr-obs): daily_emr_cluster_health enrich` | `enrich_emr_health` → `datalake_emr_health.daily_emr_cluster_health` |
| 3 | 2 | `feat(emr-obs): emr_dag_task_spine API reconstruct` | `datalake_emr_health.emr_dag_task_spine` |
| 4 | 3 | `feat(emr-obs): fact_emr_task_run and fact_emr_dag_run` | `dw_emr_health` facts (stage cols NULL) |
| 5 (top) | 4 | `feat(emr-obs): twin dag_health for EMR` | UNION twin `dag_health` (+ wow lineage) |

Scope v1: Airflow-orchestrated `emr_cluster_base` / `provisioner=emr` only —
not EMR Serverless, not unmanaged clusters.

## Cluster identity resolution

Cluster identity (`cluster_name`, `run_id`, `dag_id`) resolves events-first
from EventBridge (`datalake_emr_events_clean.events`) for clusters from
2026-08-28 onward, where `EMR Cluster State Change` events record the exact
`{dag_id}_{run_id}` cluster name.

For pre-event clusters (before 2026-08-28), identity falls back to an hour-bucket
heuristic in `emr_instance_timeline` matching CUR first billed hours against
`datalake_airflow.task_instance` create/terminate lifecycle tasks. Ambiguous
candidates leave `run_id` as NULL.

## Discovery window (EMR API)

`ListClusters` has no tag filter, so both enrich jobs used to page **every**
cluster in the account over `load_start − 14d` … `load_end + 1d` in one
paginator — that throttles on a June→now backfill.

v1 clusters last 6–8 hours, so:

- `CreatedAfter = load_start − 1 day` (not 14)
- `CreatedBefore = load_end` (exclusive end; no extra day)
- page **one calendar day at a time**, dedupe by cluster id
- `DescribeCluster` only for names matching Airflow run_id markers
  (`_scheduled`, `_manual`, `_dataset_triggered`, `_backfill`)
- boto3 adaptive retries (10 attempts)
- `emr_dag_task_spine` waits on `daily_emr_cluster_health` so the two jobs
  do not `ListClusters` at the same time

A scheduled run lists two days of clusters. A June 1 → Aug 15 backfill is
~76 small `ListClusters` calls instead of one 2.5-month dump.

AWS drops terminated clusters from `ListClusters` after ~2 months — early
June may already be gone from the API; there is no v1 CloudTrail fallback.


## References

- [View CloudWatch metrics for Amazon EMR](https://docs.aws.amazon.com/emr/latest/ManagementGuide/UsingEMR_ViewingMetrics.html)
- [Cost Explorer reports for EMR via cost allocation tags](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/create-detailed-cost-and-usage-reports-for-amazon-emr-clusters-by-using-aws-cost-explorer.html)
- Local prototypes: `local/emr_monitor/metrics.py`, `pricing.py`, `logs.py`
- Databricks parity: `dags/platform/enrich_databricks_health/`,
  `dags/platform/dw_databricks_health/`,
  `dags/platform/metric_observability__dags/queries/metric/dag_health.sql`
