---
name: right-size-cluster
description: >
  Analyzes the cluster configuration of a bi-etl-ejuice DAG and recommends
  resizing to reduce cost without unacceptably increasing runtime.
  Performs static analysis of the declaration file and SQL queries to infer
  parallelism and workload profile, reads Databricks cluster metrics (CPU,
  memory, active executors) from the Metrics tab and task logs when available
  to identify bottlenecks, applies an instance-family decision tree, validates
  compatibility with schedule_interval (prioritizing fleet instances for
  high-frequency DAGs), compares against prod_conf.yml presets, and generates
  the correct `cluster:` block. Use when the user asks to optimize a cluster,
  reduce DAG cost, assess underutilization, analyze Databricks cluster metrics
  screenshots, or size a new cluster.
---

# Right-size Cluster

## Step 1 — Collect DAG context

Read the target DAG's `*_declaration.yml`. Extract:
- `cluster.type` and `custom_configurations` (or preset name)
- `schedule_interval` → convert to **runs/day**

**Mandatory questions to the user (always ask, even if not raised):**
1. **(Existing DAGs only)** What is the current average runtime?
   — Skip this question for brand-new DAGs with no execution history. Runtime-based cost calculations (Step 7) will be marked as N/A.
2. Do you have **task logs** to share for the slowest task(s)?
3. Do you have **Databricks Metrics tab screenshots** (CPU and Container Memory, Driver and Executor node views) to share? Access via Compute → select cluster → Metrics tab.

Do not assume the answer to (2) and (3). If the user says "no" or "not available", proceed without them — Step 1b alone provides enough signal for an initial recommendation, while Steps 2 and 3 simply become no-ops.

---

## Step 1b — Static analysis of declaration and SQL

This step always runs, regardless of whether logs/cluster metrics are available. It extracts sizing signals directly from the code already in the repo.

### 1b.1 — Infer parallelism from the declaration file

From the `*_declaration.yml`:
- Count the number of tables in `tables_customization` (or, for non-tabular workflows, the number of resulting tasks inferred from SQL files in `queries/{layer}/`).
- Inspect any `inner dependencies` blocks: tasks listed there run sequentially; tasks without dependencies between them can run in parallel.
- **Max concurrent tasks** = number of tables/tasks with no blocking dependency on each other → this is the worker count the cluster needs to support concurrently.

Examples:
- 8 tables, no dependencies → up to 8 tasks in parallel → cluster needs ≥ 8 task slots
- 8 tables, all chained sequentially via dependencies → 1 task at a time → single-node candidate
- 2 independent groups of 3 dependent tasks → up to 2 tasks in parallel

### 1b.2 — Assess workload profile from SQL files

Read all files in `queries/{layer}/` and classify the most demanding query in the DAG (the heaviest one drives the sizing):

| Signal in SQL | Workload profile | Family hint |
|---|---|---|
| Only SELECTs, casts, simple WHERE filters, no JOINs | I/O-bound | `m5a` / single node; reduce workers, focus on driver |
| 2+ JOINs or large fan-out JOINs | Memory/CPU-bound | `r5a` (memory-optimized) |
| Window functions (ROW_NUMBER, RANK, LAG, LEAD, dense_rank) | Memory-bound | `r5a` |
| GROUP BY + aggregations on wide datasets | Memory/CPU-bound | `r5a` or `c5a` |
| QUALIFY + deduplication patterns | Memory-bound | `r5a` |
| MERGE INTO / OPTIMIZE / wide Delta scans | SQL-heavy | `r5a` family; do not add Photon |
| Custom Python Spark logic (no SQL or simple SQL) | Mixed — defer to logs/metrics | `m5a` or `r5a` depending on RAM usage |

Use the most demanding query as the sizing baseline. Mix of patterns → take the worst case.

### 1b.3 — Output of Step 1b

At the end of this step, record:
- **Parallelism** (max concurrent tasks)
- **Workload profile** (one of the rows above)
- **Family hint** (m5a / r5a / c5a)

These feed Step 4. They are also useful as context when logs/cluster metrics are available — because a metrics number in isolation has no meaning without knowing the expected parallelism from the declaration. Take as an example:

- **Declaration allows 8 parallel tasks, Metrics tab shows 1.5 active executors** → the workload is not actually parallelizing as expected (implicit dependencies, small data, driver bottleneck) → strong over-provisioning signal, workers should be reduced.
- **Declaration has 2 sequentially dependent tasks, Metrics tab shows 1.5 active executors** → 1.5 is close to the maximum possible (1 task at a time) → cluster is well-sized, probably no action needed.

The same metrics reading leads to opposite conclusions depending on Step 1b. Always cross-reference both.

---

## Step 2 — Analyze task logs (if available)

Skip this step if the user said no logs are available in Step 1.

Even when the issue is not purely about cluster sizing, identifying code-level bottlenecks informs independent improvements. Read logs paying attention to **timestamps** between consecutive lines.

| Pattern | Bottleneck | Action |
|---|---|---|
| Gap > 5 min between "Reading from S3" and the next log line | Full scan / S3 file listing without partition pruning | Check whether the source has date-based partitions; apply explicit path filter before passing to Spark |
| High `elapsed_time` in `S3Loader.load_df` for few output records | Full table read before the incremental filter | Partition pruning at the source or filter pushdown |
| `df.count()` called after the write | Unnecessary action (full DataFrame re-scan) | Remove or replace with a metric from the write operation |
| `OPTIMIZE ZORDER` with high runtime in a DAG that runs once a day or less | Full Delta table recompaction may be dominating the runtime | Flag to the user that ZORDER may be the bottleneck; investigate table size and incremental volume |
| Runtime >> records written (e.g. 21 min for 14k rows) | I/O bottleneck, not CPU/memory | Inform the user — reducing the cluster will not fix this |

At the end of this step, explicitly separate findings into:
- **Cluster problems** (underutilization, over-provisioning) → proceed to the next steps
- **Code/job problems** (full scan, unnecessary count, slow ZORDER) → save to report in Step 8 alongside the YAML

---

## Step 3 — Interpret monitoring metrics (if available)

Skip this step if the user said no cluster metrics screenshots are available in Step 1. Without them, rely on Step 1b's parallelism inference and the user-provided runtime estimate as the sizing inputs.

Access via **Compute → select cluster → Metrics tab**. Relevant graphs: *CPU utilization* and *Container memory usage*, on the **Driver** and **Only executor nodes** views separately.

| Signal | Interpretation |
|---|---|
| Driver CPU avg < 30% | Driver oversized or sequential job |
| Driver RAM: `used / limit` | Sets the **minimum RAM floor** for the new driver — never allocate less |
| Active executors avg << N provisioned | Excess workers |
| Executor CPU avg < 30% + active executors < 50% of total | Cluster over-provisioned |
| High steal CPU on workers | Spot instances — expected variation, not a problem signal |
| Executor RAM > 90% | OOM risk — do not reduce worker size |

**Blocking rule:** if `driver RAM used > available RAM on the new driver node`, the job will OOM. Verify before recommending any downgrade or single-node configuration.

---

## Step 4 — Instance family decision tree

### Driver (based on observed RAM usage)

| Driver RAM used | Recommended driver instance |
|---|---|
| < 8 GB | `m5a.large` (8 GB) or `m-fleet.xlarge` (~16 GB) |
| 8–16 GB | `r5a.xlarge` (32 GB) or `m5a.xlarge` (16 GB) |
| 16–32 GB | `r5a.2xlarge` (64 GB) |
| > 32 GB | **Do not upsize** — if the driver is using more than 32 GB, it is likely doing work it should not (e.g. collecting large datasets, unnecessary caching, improper broadcast). Cap recommendation at `r5a.2xlarge` and flag this to the user as a code smell to investigate. |

### Workers

**If cluster metrics are available** — base on active executors:

| Active executors (avg) | Recommended workers |
|---|---|
| 0–1 and runtime < 30 min | Attempt single node first (if driver RAM fits) |
| 0–1 and runtime ≥ 30 min | 1 worker |
| 1–2 | 1–2 workers |
| ≥ 3 with CPU > 60% | Keep 3–4 workers |

**If cluster metrics are NOT available** — base on parallelism from Step 1b:

| Max concurrent tasks (Step 1b.1) | Recommended workers |
|---|---|
| 1 | Single node (if driver RAM fits) or 1 worker |
| 2–3 | 2 workers |
| 4–6 | 3–4 workers |
| ≥ 7 | 4+ workers; consider fleet preset |

### Workload profile

| Profile | Signals | Family |
|---|---|---|
| I/O-bound + sequential | CPU and RAM slack, few active executors | Reduce workers; focus on driver |
| Memory-bound | RAM > 70%, CPU slack | `r5a` (memory-optimized) |
| CPU-bound | CPU > 70%, RAM slack | `c5a` or `m5a`; add workers |

### Photon

**Photon requires active justification before recommending.** It costs 2× DBUs and requires NVMe instances (`r5d` / `m5d`). Only consider it when **all three** conditions are met:
- Confirmed heavy SQL/Delta workload (MERGE, OPTIMIZE, wide scans)
- Expected runtime reduction > 50%
- Total cost/run is still **lower** than the non-Photon equivalent after accounting for the 2× DBU multiplier

In the absence of that evidence, default to no Photon.

If the current cluster already uses Photon, evaluate migrating to the r5a equivalent as part of the optimization — the 2× DBU overhead is rarely offset by runtime gains, and removing Photon typically yields significant cost savings without meaningful runtime regression.

---

## Step 5 — Validate schedule_interval and evaluate fleet instances

Calculate **runs/day** from `schedule_interval`:

| Frequency | Recommendation |
|---|---|
| < 24 runs/day (less than hourly) | Standard presets (SPOT_WITH_FALLBACK); startup overhead amortized |
| ≥ 24 runs/day (hourly or more frequent) | Evaluate fleet — cluster startup is a significant fraction of total runtime |
| ≥ 48 runs/day (every 30 min or more) | Strong candidate for `databricks_16_4_rfleet_instance_cluster_*` |

**When to recommend rfleet:**
- Hourly or more frequent DAG
- RAM requirement per node fits in r-fleet.xlarge (≈ 32 GB)
- Check which worker-count variant (`_2`, `_3`, `_4`, `_5`, `_7`) matches the required parallelism
- rfleet uses an on-demand pool — higher EC2 cost than spot, but instant startup justifies it at high frequency

If fleet is not suitable (RAM > 32 GB/node or DAG < 24 runs/day), keep the standard spot preset.

**Spark version:** always use `16.4.x-scala2.12` in every generated YAML (preset or `custom_configurations`).

---

## Step 6 — Select preset from prod_conf.yml

Read [`bietlejuice/prod_conf.yml`](../../../bietlejuice/prod_conf.yml) and consult [`cluster-reference.md`](cluster-reference.md) to find the closest matching preset.

**Priority order:**
1. `databricks_16_4_rfleet_instance_cluster_*` — if DAG ≥ 24 runs/day and RAM fits in r-fleet.xlarge (~32 GB/node)
2. `databricks_16_4_*` preset that best matches the family and size recommended in Step 4
3. `custom_cluster` with inline `custom_configurations` in the declaration — only if no preset satisfies RAM or workload profile requirements

Existing presets are always preferred over `custom_cluster` — they simplify maintenance and standardization.

---

## Step 7 — Calculate cost break-even

```
cost/run = (total_EC2_spot_rate + total_DBU_rate × 0.15) × runtime_hrs

DBU/hr per instance (no Photon; Photon = × 2):
  m5a.large: 0.5   | m5a.xlarge: 1.0  | m5a.2xlarge: 2.0
  r5a.large: 0.5   | r5a.xlarge: 1.0  | r5a.2xlarge: 2.0  | r5a.4xlarge: 4.0
  c5a.2xlarge: 2.0
  m-fleet.xlarge: 1.0 | m-fleet.2xlarge: 2.0 | m-fleet.4xlarge: 4.0
  r-fleet.xlarge (on-demand pool): 1.0

EC2 prices (us-east-1) — use spot average for cost estimates; spot min as best-case floor:
  m5a.large:   spot avg $0.04  | spot min $0.04  | on-demand $0.09
  m5a.xlarge:  spot avg $0.09  | spot min $0.08  | on-demand $0.17
  m5a.2xlarge: spot avg $0.17  | spot min $0.12  | on-demand $0.34
  r5a.large:   spot avg $0.05  | spot min $0.04  | on-demand $0.11
  r5a.xlarge:  spot avg $0.10  | spot min $0.09  | on-demand $0.23
  r5a.2xlarge: spot avg $0.21  | spot min $0.19  | on-demand $0.45
  r5a.4xlarge: spot avg $0.41  | spot min $0.37  | on-demand $0.90
  c5a.2xlarge: spot avg $0.17  | spot min $0.16  | on-demand $0.31
  r5d.large:   spot avg $0.08  | spot min $0.07  | on-demand $0.14
  r5d.xlarge:  spot avg $0.18  | spot min $0.17  | on-demand $0.29
  r5d.2xlarge: spot avg $0.34  | spot min $0.26  | on-demand $0.58
  r5d.4xlarge: spot avg $0.68  | spot min $0.57  | on-demand $1.15
  m-fleet.xlarge: $0.06 | m-fleet.2xlarge: $0.10 | m-fleet.4xlarge: $0.18  (approximate)
  r-fleet.xlarge (on-demand pool): $0.25  (approximate)

break-even_runtime_min = current_cost_per_run / (new_cost_rate_per_hr / 60)
```

Present to the user:
- Current cost/run vs. new cost/run (at the same runtime)
- % savings
- Break-even runtime (in minutes) — above this the new cluster costs more
- Estimated annual savings = (current_cost - new_cost) × runs/day × 365

---

## Step 8 — Generate the final YAML and complete summary

### `cluster:` block examples

**Standard preset:**
```yaml
cluster:
  type: databricks_16_4_min_io-memory_cluster
```

**Fleet preset (high-frequency DAG):**
```yaml
cluster:
  type: databricks_16_4_rfleet_instance_cluster_3_workers
```

**custom_cluster (when no preset fits):**
```yaml
cluster:
  type: custom_cluster
  databricks_conn_id: databricks_new
  custom_configurations:
    driver_node_type_id: r5a.2xlarge
    node_type_id: r5a.xlarge
    num_workers: 2
    spark_version: 16.4.x-scala2.12
```

**Single node:**
```yaml
cluster:
  type: databricks_16_4_small_general_fleet_2xlarge_single_node
```

### Always include after the YAML:

**Cluster warnings:**
- If estimated new runtime > `schedule_interval` → warn about Airflow run accumulation risk
- If workers were reduced → recommend running a manual test run before applying to production

**Code/job bottlenecks (from Step 2):**
List separately from cluster issues, using this format:

```
Issue: [description]
Impact: [estimated wasted time]
Action: [what to change and where]
```

These are independent of the cluster and should be addressed even after the cluster is optimized.
