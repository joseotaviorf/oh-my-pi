# Cluster Reference — bi-etl-ejuice

Presets available in `bietlejuice/prod_conf.yml` for use in the `cluster.type` key of a declaration. All use `spark_version: 16.4.x-scala2.12`. Costs are estimates (spot us-east-1 + DBU Jobs Compute ~$0.10/DBU-hr).

---

## General (m5a) — balanced, no Photon

| Preset | Driver | Workers | Total vCPU | Total RAM | DBU/hr | Cost/hr | Best for |
|---|---|---|---|---|---|---|---|
| `databricks_16_4_min_general_cluster` | m5a.large | 2× m5a.large | 6 | 24 GB | 1.5 | ~$0.27 | Light jobs, small tables |
| `databricks_16_4_med_general_2_workers_cluster` | m5a.xlarge | 2× m5a.xlarge | 12 | 48 GB | 3.0 | ~$0.57 | Moderate ETL, few transformations |
| `databricks_16_4_med_general_cluster` | m5a.xlarge | 3× m5a.xlarge | 16 | 64 GB | 4.0 | ~$0.76 | Moderate ETL with more parallelism |
| `databricks_16_4_med_general_driver_2_min_workers_cluster` | m5a.xlarge | 2× m5a.large | 8 | 40 GB | 2.0 | ~$0.37 | Driver-heavy jobs with smaller workers |

---

## Memory (r5a) — memory-optimized, no Photon

| Preset | Driver | Workers | Total vCPU | Total RAM | DBU/hr | Cost/hr | Best for |
|---|---|---|---|---|---|---|---|
| `databricks_16_4_xmin_memory_cluster` | r5a.large | 2× r5a.large | 6 | 48 GB | 1.5 | ~$0.30 | Light jobs with memory pressure |
| `databricks_16_4_xmin_view_cluster` | m5.large | 1× m5.large | 4 | 16 GB | 1.0 | ~$0.17 | Views, minimal jobs |
| `databricks_16_4_min_io-memory_cluster` | r5a.large | 2× r5a.xlarge | 10 | 80 GB | 2.5 | ~$0.50 | Incremental ingestion with joins, light enrich |
| `databricks_16_4_med_memory_2_workers_general_cluster` | r5a.xlarge | 2× r5a.xlarge | 12 | 96 GB | 3.0 | ~$0.60 | Medium enrich/DW, moderate joins |
| `databricks_16_4_med_memory_general_cluster` | r5a.xlarge | 3× r5a.xlarge | 16 | 128 GB | 4.0 | ~$0.80 | Enrich/DW with higher parallelism |
| `databricks_16_4_min_2xlarge_memory_cluster` | r5a.2xlarge | 3× r5a.2xlarge | 32 | 256 GB | 8.0 | ~$1.64 | Jobs with large in-memory datasets |
| `databricks_16_4_high_mem_driver_high_mem_nodes_3_workers` | r5a.4xlarge | 3× r5a.4xlarge | 64 | 512 GB | 16.0 | ~$3.24 | Extremely memory-bound jobs |

---

## Memory + Photon (r5d) — NVMe, Photon 2× DBU

> **Photon requires active justification before recommending.** These presets are documented for reference only. If a DAG currently uses a Photon preset, evaluate migrating to the equivalent r5a preset — Photon's 2× DBU cost is rarely offset by runtime gains, and switching typically yields significant cost savings without meaningful runtime regression.

| Preset | Driver | Workers | Total vCPU | Total RAM | DBU/hr | Cost/hr | Best for |
|---|---|---|---|---|---|---|---|
| `databricks_16_4_min_io-memory_photon_cluster` | r5d.large | 2× r5d.xlarge | 10 | 80 GB | 5.0 | ~$0.94 | Minimal Photon SQL/Delta incremental |
| `databricks_16_4_med_mem_driver_min_memory_2_nodes_photon_cluster` | r5d.2xlarge | 2× r5d.xlarge | 16 | 128 GB | 8.0 | ~$1.50 | Heavy driver + smaller Photon workers |
| `databricks_16_4_min_memory_photon_cluster` | r5d.2xlarge | 2× r5d.2xlarge | 24 | 192 GB | 12.0 | ~$2.22 | Memory-bound jobs + medium Photon |
| `databricks_16_4_med_io-memory_photon_cluster` | r5d.2xlarge | 3× r5d.4xlarge | 56 | 448 GB | 28.0 | ~$5.18 | Heavy DW, Delta MERGE/OPTIMIZE on large tables |
| `databricks_16_4_xmed_io-memory_photon_cluster` | r5d.xlarge | 3× r5d.4xlarge | 52 | 416 GB | 26.0 | ~$4.82 | Same as above, slightly smaller driver |

---

## Single node (m-fleet) — `local[*]`, no workers

> Useful for light sequential jobs. **Always verify driver RAM before using** — the driver uses the full node's memory.

| Preset | Instance | vCPU | RAM | DBU/hr | Cost/hr | Use when |
|---|---|---|---|---|---|---|
| `databricks_16_4_small_general_fleet_xlarge_single_node` | m-fleet.xlarge | ~4 | ~16 GB | 1.0 | ~$0.16 | Driver uses < 12 GB |
| `databricks_16_4_small_general_fleet_2xlarge_single_node` | m-fleet.2xlarge | ~8 | ~32 GB | 2.0 | ~$0.30 | Driver uses 12–26 GB |
| `databricks_16_4_small_general_fleet_4xlarge_single_node` | m-fleet.4xlarge | ~16 | ~64 GB | 4.0 | ~$0.58 | Driver uses 26–52 GB |
| `databricks_16_4_small_general_fleet_8xlarge_single_node` | m-fleet.8xlarge | ~32 | ~128 GB | 8.0 | ~$1.10 | Driver uses > 52 GB |

---

## Fleet pool (rfleet) — on-demand, instant startup

> For DAGs with hourly or more frequent `schedule_interval` (≥ 24 runs/day). Uses a pre-allocated on-demand pool — no startup latency, but higher EC2 cost than spot. r-fleet.xlarge instances ≈ 4 vCPU, 32 GB RAM (on-demand ~$0.25/hr/node).

| Preset | Workers | Total nodes | Total vCPU | Total RAM | DBU/hr | Cost/hr | Best for |
|---|---|---|---|---|---|---|---|
| `databricks_16_4_rfleet_instance_cluster` | 2 | 3 | ~12 | ~96 GB | 3.0 | ~$1.05 | Hourly DAG, light-to-moderate load |
| `databricks_16_4_rfleet_instance_cluster_3_workers` | 3 | 4 | ~16 | ~128 GB | 4.0 | ~$1.40 | Hourly DAG, moderate load |
| `databricks_16_4_rfleet_instance_cluster_4_workers` | 4 | 5 | ~20 | ~160 GB | 5.0 | ~$1.75 | Hourly DAG, moderate-to-high load |
| `databricks_16_4_rfleet_instance_cluster_5_workers` | 5 | 6 | ~24 | ~192 GB | 6.0 | ~$2.10 | Hourly DAG, high load |
| `databricks_16_4_rfleet_instance_cluster_7_workers` | 7 | 8 | ~32 | ~256 GB | 8.0 | ~$2.75 | Hourly DAG, very high load |

**Note:** rfleet is not recommended if the job needs > 32 GB per node — use r5a spot presets instead.

---

## DBU reference per instance type

| Instance | vCPU | RAM | DBU/hr (no Photon) | EC2 spot avg/hr |
|---|---|---|---|---|
| m5a.large | 2 | 8 GB | 0.5 | ~$0.04 |
| m5a.xlarge | 4 | 16 GB | 1.0 | ~$0.09 |
| m5a.2xlarge | 8 | 32 GB | 2.0 | ~$0.17 |
| r5a.large | 2 | 16 GB | 0.5 | ~$0.05 |
| r5a.xlarge | 4 | 32 GB | 1.0 | ~$0.10 |
| r5a.2xlarge | 8 | 64 GB | 2.0 | ~$0.21 |
| r5a.4xlarge | 16 | 128 GB | 4.0 | ~$0.41 |
| c5a.2xlarge | 8 | 16 GB | 2.0 | ~$0.17 |
| r5d.large | 2 | 16 GB | 1.0¹ | ~$0.08 |
| r5d.xlarge | 4 | 32 GB | 2.0¹ | ~$0.18 |
| r5d.2xlarge | 8 | 64 GB | 4.0¹ | ~$0.34 |
| r5d.4xlarge | 16 | 128 GB | 8.0¹ | ~$0.68 |
| m-fleet.xlarge | ~4 | ~16 GB | 1.0 | ~$0.06 (approx) |
| m-fleet.2xlarge | ~8 | ~32 GB | 2.0 | ~$0.10 (approx) |
| m-fleet.4xlarge | ~16 | ~64 GB | 4.0 | ~$0.18 (approx) |
| r-fleet.xlarge (pool) | ~4 | ~32 GB | 1.0 | ~$0.25 on-demand (approx) |

¹ r5d instances used with Photon: multiply DBU/hr by **2×**. Photon is not recommended for new configurations.

---

## Quick selection guide

```
Runs/day ≥ 24 (hourly or more frequent)?
  Yes → rfleet_instance_cluster_* (if RAM/node ≤ 32 GB)
  No  → continue

Photon? Requires active justification — all three must be true:
  1. Heavy SQL/Delta workload confirmed (MERGE, OPTIMIZE, wide scans)
  2. Expected runtime reduction > 50%
  3. Total cost/run is still lower than the r5a equivalent after the 2× DBU multiplier
  Default: no Photon — prefer r5a equivalents.
  If currently using Photon: evaluate migrating to r5a — the 2× DBU cost is rarely
  offset by runtime gains, and switching typically yields significant cost savings.

Driver RAM used:
  < 8 GB   → min_general or single node xlarge
  8–16 GB  → min_io-memory or med_general
  16–32 GB → med_memory_*_workers or custom_cluster with r5a.2xlarge driver
  > 32 GB  → cap at r5a.2xlarge; flag driver as likely doing work it should not

Workers needed:
  0–1 (runtime < 30 min) → single node first (verify RAM)
  0–1 (runtime ≥ 30 min) → 1 worker
  2   → *_2_workers_cluster
  3   → *_cluster (default 3 workers)
  4+  → custom_cluster or high_mem_*
```
