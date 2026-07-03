# EMLIO DAG — June 2026 Task Timing & Cost Analysis

**DAG:** `bietlejuice.emlio` (prod)  
**Source:** `dw_databricks_health.fact_databricks_task_run`  
**Analysis date:** 2026-07-02  
**Owner:** MLOps

---

## Executive summary

- **4 core tasks:** `load-raw-emlio-logs`, `load-clean-emlio-logs`, `sync-metadata-raw-emlio-logs`, `sync-metadata-clean-emlio-logs`
- **`sync-metadata-raw-emlio-logs` is the main problem** — from **Jun 17–26** it hit the **~2h timeout on every attempt** (3× per day), matching Airflow retry behavior
- **`sync-metadata-clean-emlio-logs`** is never an issue (~0.2–0.5m, single attempt)
- **`load-clean-emlio-logs`** gets pulled into retries when sync-raw times out (cancelled attempts Jun 17–26), but usually succeeds on the last try
- **`load-raw-emlio-logs`** is slower after Jun 13 (55–80m → 140–208m) but **always single attempt, always succeeds**
- **Recovery:** Jun 27 sync-raw succeeded on 3rd attempt; **Jun 28–30** back to single successful runs (~113–118m)

**Legend:** ✓ succeeded · ⏱ timed out (~120m) · ✗ cancelled (Airflow retry)

---

## What each task actually does (master `dags/mlops/emlio/`)

From `emlio_declaration.yml` + `RawCustomIngestionWorkflow`:

| Airflow task | What it runs | Data work |
|--------------|--------------|-----------|
| **`load-raw-emlio-logs`** | Spark job `load_emlio_raw.py` | Kafka structured streaming → parse JSON from `value` → write **raw** Delta (`datalake_emlio_raw.emlio_logs`) |
| **`sync-metadata-raw-emlio-logs`** | Metastore sync (`sync_metadata`) | Propagate raw table metadata to Hive/Glue catalog — **not a data load** |
| **`load-clean-emlio-logs`** | SQL in `queries/clean/emlio_logs.sql` via `LOAD_DELTA` | `SELECT … FROM datalake_emlio_raw.emlio_logs WHERE year/month/day` → write **clean** Delta (repartitioned by `id_service`) |
| **`sync-metadata-clean-emlio-logs`** | Metastore sync | Same idea for clean table (~0.3m) |

**DAG order** (`raw_custom_ingestion_workflow.py`):

```
load-raw  →  sync-metadata-raw  →  (cluster finish)
    ↓
load-clean  →  register-table  →  sync-metadata-clean  →  optimize
```

So **`load-clean` reads already-written raw Delta for one day** — it does not re-ingest from Kafka.

The clean SQL is a column rename + filter on one partition:

```sql
SELECT uuid, service_id AS id_service, ...
FROM datalake_emlio_raw.emlio_logs
WHERE year = {year} AND month = {month} AND day = {day}
```

Raw is the heavy job: Kafka consumer, JSON explode, streaming checkpoint, write raw files.

---

## Why does clean sometimes *look* slower than raw?

**Your intuition is correct:** on a **single successful run**, raw is slower than clean. When clean appears slower in the tables, it is usually a **measurement / retry artifact**.

### 1. On normal days, raw IS slower

| Period | load-raw | load-clean |
|--------|----------|------------|
| Jun 1–12 (stable) | **~55–81 min** | **~33–38 min** |
| Jun 28–30 (recovered) | **~140–146 min** | **~114–119 min** |

Raw is slower in **every single-day successful comparison** in June.

### 2. Jun 17–26: retries, not one clean run

Example **Jun 18**:

| Task | Attempts | What happened |
|------|----------|---------------|
| load-raw | **1×** | 201.8m ✓ |
| load-clean | **3×** | 124m ✗ → 128m ✗ → **147m ✓** |
| sync-metadata-raw | **3×** | 120m ⏱ → 120m ⏱ → 120m ⏱ |

If you **sum** clean attempts: **~399 min** — looks worse than raw's **202 min**.  
But the **successful** clean run (**147 min**) is still **shorter** than raw (**202 min**).

The first two clean attempts were **CANCELLED** (~124m), not failed transforms — likely Airflow/Databricks killing/retrying while **`sync-metadata-raw` is stuck at the 2h ceiling** on the same cluster run.

### 3. Don't compare load-clean to sync-metadata-raw

The real problem task is **`sync-metadata-raw-emlio-logs`** — it is **not a data load**. It is catalog propagation, and it hit **~120m timeouts** daily Jun 17–26. That matches what Airflow shows.

Jun 18 sync-raw alone: **3 × 120m = 360m of timeout wall time**, while load-raw succeeded once in 202m.

| Question | Answer |
|----------|--------|
| Should clean be faster than raw? | **Yes** — and on successful single runs, it **is**. |
| Why does the table look inverted? | **Retry stacking** on `load-clean` (cancelled attempts) + confusing **`sync-metadata-raw`** (metadata, not load) with the loads. |
| What's actually broken? | **`sync-metadata-raw-emlio-logs`** timing out at ~2h — not the clean SQL transform itself. |

---

## June daily durations (prod)

| Date | load-raw | load-clean | sync-raw | sync-clean |
|------|----------|------------|----------|------------|
| Jun 01 | 56.8m ✓ | 32.8m ✓ | 31.8m ✓ | 0.4m ✓ |
| Jun 02 | 64.8m ✓ | 35.5m ✓ | 35.5m ✓ | 0.5m ✓ |
| Jun 03 | 61.4m ✓ | 35.7m ✓ | 34.6m ✓ | 0.4m ✓ |
| Jun 04 | 60.8m ✓ | 34.9m ✓ | 34.6m ✓ | 0.4m ✓ |
| Jun 05 | 57.6m ✓ | 34.8m ✓ | 34.8m ✓ | 0.5m ✓ |
| Jun 06 | 60.2m ✓ | 32.6m ✓ | 32.6m ✓ | 0.4m ✓ |
| Jun 07 | 54.9m ✓ | 33.4m ✓ | 32.4m ✓ | 0.4m ✓ |
| Jun 08 | 54.9m ✓ | 32.5m ✓ | 31.7m ✓ | 0.4m ✓ |
| Jun 09 | 67.5m ✓ | 41.9m ✓ | 41.4m ✓ | 0.4m ✓ |
| Jun 10 | 63.8m ✓ | 36.2m ✓ | 35.2m ✓ | 0.4m ✓ |
| Jun 11 | 63.7m ✓ | 37.2m ✓ | 37.1m ✓ | 0.4m ✓ |
| Jun 12 | 81.0m ✓ | 38.5m ✓ | 38.5m ✓ | 0.4m ✓ |
| Jun 13 | 113.2m ✓ | 90.4m ✓ | 89.3m ✓ | 0.3m ✓ |
| Jun 14 | 112.9m ✓ | 67.2m ✓ | 66.3m ✓ | 0.3m ✓ |
| Jun 15 | 94.7m ✓ | 70.6m ✓ | 69.6m ✓ | 0.4m ✓ |
| Jun 16 | 133.8m ✓ | 110.0m ✓ | 109.4m ✓ | 0.4m ✓ |
| Jun 17 | 198.4m ✓ | **3×** 123.8m ✗ → 126.5m ✗ → 143.4m ✓ | **3×** 120.3m ⏱ → 120.2m ⏱ → 120.3m ⏱ | 0.3m ✓ |
| Jun 18 | 201.8m ✓ | **3×** 124.1m ✗ → 127.7m ✗ → 147.1m ✓ | **3×** 120.1m ⏱ → 120.2m ⏱ → 120.2m ⏱ | 0.3m ✓ |
| Jun 19 | 184.1m ✓ | **3×** 125.2m ✗ → 127.0m ✗ → 145.2m ✓ | **3×** 120.2m ⏱ → 120.2m ⏱ → 120.1m ⏱ | 0.3m ✓ |
| Jun 20 | 165.9m ✓ | **2×** 124.1m ✗ → 124.9m ✓ | **3×** 120.2m ⏱ → 120.2m ⏱ → 120.3m ⏱ | 0.3m ✓ |
| Jun 21 | 140.9m ✓ | 117.3m ✓ | 116.4m ✓ | 0.4m ✓ |
| Jun 22 | 159.8m ✓ | **3×** 124.4m ✗ → 126.2m ✗ → 129.8m ✓ | **3×** 120.3m ⏱ → 120.2m ⏱ → 120.2m ⏱ | 0.3m ✓ |
| Jun 23 | 208.1m ✓ | **3×** 124.0m ✗ → 130.2m ✗ → 149.2m ✓ | **3×** 120.5m ⏱ → 120.6m ⏱ → 120.7m ⏱ | 0.3m ✓ |
| Jun 24 | 177.6m ✓ | **3×** 125.8m ✗ → 127.3m ✗ → 142.4m ✓ | **3×** 120.2m ⏱ → 120.7m ⏱ → 120.5m ⏱ | 0.3m ✓ |
| Jun 25 | 178.9m ✓ | **3×** 125.2m ✗ → 126.3m ✗ → 143.4m ✓ | **3×** 120.7m ⏱ → 120.6m ⏱ → 120.7m ⏱ | 0.3m ✓ |
| Jun 26 | 167.0m ✓ | **3×** 126.2m ✗ → 127.3m ✗ → 142.0m ✓ | **3×** 120.7m ⏱ → 120.7m ⏱ → 120.7m ⏱ | 0.3m ✓ |
| Jun 27 | 161.1m ✓ | **2×** 123.9m ✗ → 121.5m ✓ | **3×** 120.1m ⏱ → 120.2m ⏱ → **68.9m ✓** | 0.2m ✓ |
| Jun 28 | 139.7m ✓ | 113.9m ✓ | 113.2m ✓ | 0.3m ✓ |
| Jun 29 | 140.0m ✓ | 116.6m ✓ | 115.7m ✓ | 0.2m ✓ |
| Jun 30 | 146.1m ✓ | 119.2m ✓ | 118.2m ✓ | 0.3m ✓ |

---

## Phase breakdown

### `sync-metadata-raw-emlio-logs` (primary issue)

| Phase | sync-raw behavior |
|-------|-------------------|
| **Jun 1–12** | ~32–38m, 1 attempt, always ✓ |
| **Jun 13–16** | Slower (66–109m) but still ✓ |
| **Jun 17–26** | **3× TIMED_OUT at ~120m every day** (2h ceiling) — **never succeeded** |
| **Jun 27** | 2 timeouts, then **68.9m ✓** on 3rd attempt |
| **Jun 28–30** | Back to ~113–118m, single ✓ |

### Other tasks

| Task | Behavior |
|------|----------|
| **`sync-metadata-clean-emlio-logs`** | Never an issue — always **~0.2–0.5m**, single attempt |
| **`load-clean-emlio-logs`** | Retries when sync-raw times out (2–3 **CANCELLED** attempts Jun 17–26); usually succeeds on last try |
| **`load-raw-emlio-logs`** | Slower after Jun 13 but **always single attempt, always ✓** |

---

## Example: Jun 18 (worst-day pattern)

| Task | Attempts | Detail |
|------|----------|--------|
| load-raw | 1× | 201.8m ✓ (03:30 → 06:52 UTC) |
| sync-raw | 3× | 120.1m ⏱ → 120.2m ⏱ → 120.2m ⏱ — **all hit 2h limit** |
| load-clean | 3× | 124.1m ✗ → 127.7m ✗ → 147.1m ✓ |
| sync-clean | 1× | 0.3m ✓ |

Cost spike is mostly **~360m of wasted sync-raw wall time per day** (3 × 120m timeouts), plus cascade retries on load-clean.

---

## `sync-metadata-raw-emlio-logs` — full retry detail

| Date | Attempt | State | Start (UTC) | End (UTC) | Duration |
|------|---------|-------|-------------|-----------|----------|
| 2026-06-01 | 1/1 | SUCCEEDED | 2026-06-01 04:27:11.701 | 2026-06-01 04:58:57.072 | 31.8m |
| 2026-06-02 | 1/1 | SUCCEEDED | 2026-06-02 04:35:08.043 | 2026-06-02 05:10:39.798 | 35.5m |
| 2026-06-03 | 1/1 | SUCCEEDED | 2026-06-03 04:32:02.711 | 2026-06-03 05:06:37.742 | 34.6m |
| 2026-06-04 | 1/1 | SUCCEEDED | 2026-06-04 04:31:15.717 | 2026-06-04 05:05:49.958 | 34.6m |
| 2026-06-05 | 1/1 | SUCCEEDED | 2026-06-05 04:27:59.926 | 2026-06-05 05:02:48.026 | 34.8m |
| 2026-06-06 | 1/1 | SUCCEEDED | 2026-06-06 04:30:31.308 | 2026-06-06 05:03:09.473 | 32.6m |
| 2026-06-07 | 1/1 | SUCCEEDED | 2026-06-07 04:25:15.856 | 2026-06-07 04:57:40.031 | 32.4m |
| 2026-06-08 | 1/1 | SUCCEEDED | 2026-06-08 04:25:17.989 | 2026-06-08 04:56:58.361 | 31.7m |
| 2026-06-09 | 1/1 | SUCCEEDED | 2026-06-09 04:37:57.464 | 2026-06-09 05:19:22.660 | 41.4m |
| 2026-06-10 | 1/1 | SUCCEEDED | 2026-06-10 04:34:07.741 | 2026-06-10 05:09:18.235 | 35.2m |
| 2026-06-11 | 1/1 | SUCCEEDED | 2026-06-11 04:34:02.432 | 2026-06-11 05:11:06.897 | 37.1m |
| 2026-06-12 | 1/1 | SUCCEEDED | 2026-06-12 04:51:43.196 | 2026-06-12 05:30:14.407 | 38.5m |
| 2026-06-13 | 1/1 | SUCCEEDED | 2026-06-13 05:24:14.462 | 2026-06-13 06:53:30.589 | 89.3m |
| 2026-06-14 | 1/1 | SUCCEEDED | 2026-06-14 05:23:25.486 | 2026-06-14 06:29:44.659 | 66.3m |
| 2026-06-15 | 1/1 | SUCCEEDED | 2026-06-15 05:05:40.214 | 2026-06-15 06:15:16.176 | 69.6m |
| 2026-06-16 | 1/1 | SUCCEEDED | 2026-06-16 05:44:16.965 | 2026-06-16 07:33:37.667 | 109.4m |
| 2026-06-17 | 1/3 | **TIMED_OUT** | 2026-06-17 06:49:20.641 | 2026-06-17 08:49:39.195 | 120.3m |
| 2026-06-17 | 2/3 | **TIMED_OUT** | 2026-06-17 08:53:10.966 | 2026-06-17 10:53:24.726 | 120.2m |
| 2026-06-17 | 3/3 | **TIMED_OUT** | 2026-06-17 10:59:43.546 | 2026-06-17 12:59:58.321 | 120.3m |
| 2026-06-18 | 1/3 | **TIMED_OUT** | 2026-06-18 06:52:10.558 | 2026-06-18 08:52:17.528 | 120.1m |
| 2026-06-18 | 2/3 | **TIMED_OUT** | 2026-06-18 08:56:20.143 | 2026-06-18 10:56:33.707 | 120.2m |
| 2026-06-18 | 3/3 | **TIMED_OUT** | 2026-06-18 11:04:04.091 | 2026-06-18 13:04:13.876 | 120.2m |
| 2026-06-19 | 1/3 | **TIMED_OUT** | 2026-06-19 06:34:29.866 | 2026-06-19 08:34:42.141 | 120.2m |
| 2026-06-19 | 2/3 | **TIMED_OUT** | 2026-06-19 08:39:46.621 | 2026-06-19 10:39:59.535 | 120.2m |
| 2026-06-19 | 3/3 | **TIMED_OUT** | 2026-06-19 10:46:50.044 | 2026-06-19 12:46:57.467 | 120.1m |
| 2026-06-20 | 1/3 | **TIMED_OUT** | 2026-06-20 06:16:15.071 | 2026-06-20 08:16:24.002 | 120.2m |
| 2026-06-20 | 2/3 | **TIMED_OUT** | 2026-06-20 08:20:26.008 | 2026-06-20 10:20:35.345 | 120.2m |
| 2026-06-20 | 3/3 | **TIMED_OUT** | 2026-06-20 10:27:27.332 | 2026-06-20 12:27:44.464 | 120.3m |
| 2026-06-21 | 1/1 | SUCCEEDED | 2026-06-21 05:51:16.875 | 2026-06-21 07:47:42.505 | 116.4m |
| 2026-06-22 | 1/3 | **TIMED_OUT** | 2026-06-22 06:10:11.408 | 2026-06-22 08:10:27.188 | 120.3m |
| 2026-06-22 | 2/3 | **TIMED_OUT** | 2026-06-22 08:14:37.053 | 2026-06-22 10:14:50.050 | 120.2m |
| 2026-06-22 | 3/3 | **TIMED_OUT** | 2026-06-22 10:20:55.317 | 2026-06-22 12:21:05.591 | 120.2m |
| 2026-06-23 | 1/3 | **TIMED_OUT** | 2026-06-23 06:58:31.188 | 2026-06-23 08:59:01.770 | 120.5m |
| 2026-06-23 | 2/3 | **TIMED_OUT** | 2026-06-23 09:02:38.304 | 2026-06-23 11:03:12.652 | 120.6m |
| 2026-06-23 | 3/3 | **TIMED_OUT** | 2026-06-23 11:12:53.295 | 2026-06-23 13:13:37.318 | 120.7m |
| 2026-06-24 | 1/3 | **TIMED_OUT** | 2026-06-24 06:28:01.275 | 2026-06-24 08:28:11.697 | 120.2m |
| 2026-06-24 | 2/3 | **TIMED_OUT** | 2026-06-24 08:33:53.796 | 2026-06-24 10:34:34.027 | 120.7m |
| 2026-06-24 | 3/3 | **TIMED_OUT** | 2026-06-24 10:41:12.699 | 2026-06-24 12:41:43.120 | 120.5m |
| 2026-06-25 | 1/3 | **TIMED_OUT** | 2026-06-25 06:29:16.559 | 2026-06-25 08:29:55.252 | 120.7m |
| 2026-06-25 | 2/3 | **TIMED_OUT** | 2026-06-25 08:34:30.808 | 2026-06-25 10:35:08.013 | 120.6m |
| 2026-06-25 | 3/3 | **TIMED_OUT** | 2026-06-25 10:40:49.115 | 2026-06-25 12:41:30.976 | 120.7m |
| 2026-06-26 | 1/3 | **TIMED_OUT** | 2026-06-26 06:17:22.378 | 2026-06-26 08:18:05.166 | 120.7m |
| 2026-06-26 | 2/3 | **TIMED_OUT** | 2026-06-26 08:23:40.548 | 2026-06-26 10:24:19.071 | 120.7m |
| 2026-06-26 | 3/3 | **TIMED_OUT** | 2026-06-26 10:31:03.724 | 2026-06-26 12:31:42.900 | 120.7m |
| 2026-06-27 | 1/3 | **TIMED_OUT** | 2026-06-27 06:11:30.394 | 2026-06-27 08:11:36.340 | 120.1m |
| 2026-06-27 | 2/3 | **TIMED_OUT** | 2026-06-27 08:15:26.003 | 2026-06-27 10:15:38.244 | 120.2m |
| 2026-06-27 | 3/3 | SUCCEEDED | 2026-06-27 10:22:35.852 | 2026-06-27 11:31:26.348 | 68.9m |
| 2026-06-28 | 1/1 | SUCCEEDED | 2026-06-28 05:50:05.626 | 2026-06-28 07:43:15.213 | 113.2m |
| 2026-06-29 | 1/1 | SUCCEEDED | 2026-06-29 05:50:22.698 | 2026-06-29 07:46:05.331 | 115.7m |
| 2026-06-30 | 1/1 | SUCCEEDED | 2026-06-30 05:57:22.024 | 2026-06-30 07:55:35.963 | 118.2m |

---

## Cluster spec timeline (context)

| Date | Event |
|------|-------|
| **Jun 12** (git) | Prod spec cut: `consolidation_xl` (`c6g.xlarge`, 4 workers) → `consolidation_l` (`r6g.large`, 3 workers) |
| **Jun 13** (runtime) | First prod runs on `r6g.large` — wall time already creeping up |
| **Jun 15** (git) | Gen-7 validation spec added: `r7g.large` driver + `r7g.2xlarge` workers |
| **Jun 16** (git) | Gen-7 promoted to prod config: `consolidation_m_memory_cluster` + `r7g.large` |
| **Jun 17** (runtime) | First prod runs on Gen-7 — cost/duration spike |
| **Jun 20** (promotion) | Manual override: emlio promoted despite validation wall 281.5m > 30m; timeout raised to 6h |
| **Jun 22** (git merge) | Validation block removed from prod cluster spec |

Validation runs were **~72% cheaper per run** than prod during the timeout window.

---

## Recommended follow-ups

1. Investigate why **`sync-metadata-raw-emlio-logs`** exceeds the **2h task limit** on the new cluster spec (Jun 17–26)
2. Compare **prod vs validation** cluster sizing for this specific task
3. Consider whether the **2h task timeout** should be raised, or whether the sync job needs optimization / more compute
4. Monitor post-Jun 28 runs to confirm stability (single-attempt success at ~115m)
