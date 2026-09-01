---
name: salesforce-cdc-cluster-pool
description: >-
  Adds or reviews Airflow 1-slot lineage pools for bietlejuice.salesforce_cdc
  Databricks clusters. Every new cluster lineage (dedicated event or pooled
  index) must get a pool. Use when adding a Salesforce CDC cluster, dedicated
  event (case, email_message, or a new one), NUMBER_OF_POOLED_CLUSTERS,
  execute_cdc_cluster_*, ensure_lineage_pool, wait_previous_lineage, or editing
  dags/support_and_service/salesforce_cdc/salesforce_cdc.py or astro/local_pools.json.
---

# Salesforce CDC — cluster Airflow pools

Canonical DAG: `dags/support_and_service/salesforce_cdc/salesforce_cdc.py`.
Local pool registry: `astro/local_pools.json`.
Origin: [PR #28002](https://github.com/quintoandar/bi-etl-ejuice/pull/28002).

**Hard rule:** when adding a new cluster, always add it to the pool. A cluster
lineage without a 1-slot Airflow pool is a bug.

---

## Two different "pools" (do not mix)

| Term | What it is | Where |
|------|------------|--------|
| **Airflow lineage pool** (this skill) | 1 worker slot that serializes hours of **one** cluster lineage | `ensure_lineage_pool`, `pool=` on every task, `astro/local_pools.json` |
| **Event job pool** | Splits leftover CDC events across Databricks clusters `0` and `1` | `NUMBER_OF_POOLED_CLUSTERS` + `job_pool` in the DAG `with` block |

Adding a dedicated cluster (`case`, `email_message`, …) is **not** the event
job pool. It still **must** get an Airflow lineage pool.

---

## Expected behavior

Hourly DAG (`schedule_interval="0 * * * *"`, `max_active_runs=24`, `catchup=True`).
Each cluster is its own root/sink (no shared `start_salesforce` / `end_salesforce`).

### Independent lineages (cross-cluster)

Case, Email Message, and pooled clusters **must not block each other**.

If pooled cluster `0` is still on hour 14:00, Case may already be on 16:00.
That is why `max_active_runs=24`: up to a day of DAG runs can stay **open** so
a healthy lineage keeps catching up. It does **not** mean 24 hours of the
**same** cluster run in parallel.

### Serial hours (same cluster)

Never run two hours of the **same** cluster at once. No overlapping
`execute_cdc_cluster_{id}` (and no overlapping raw/clean/metrics/DLQ for that
lineage).

Enforced by **all three** together:

1. **1-slot Airflow pool** `salesforce_cdc_cluster_{cluster_id}` — workers can
   occupy only one hour of that lineage at a time.
2. **`wait_previous_lineage_{cluster_id}`** — `depends_on_past=True` and
   `wait_for_downstream=True`, wired to both `execute_cdc_cluster_*` and
   `end_cdc_cluster_*`, so hour N+1 does not start until hour N's **full**
   lineage succeeded.
3. **`execute_cdc_cluster_*`** — `depends_on_past=True` and
   `wait_for_downstream=True` (wired to `end_cdc_cluster_*`) so the next hour's
   cluster does not start until this hour's execute **and** the lineage leaf
   succeeded.

`max_active_runs=24` without the 1-slot pool would let many hours of Case
schedule Databricks jobs at once. The pool is what keeps serialization.

### What a lineage looks like

```
wait_previous_lineage_{id} ─┬─► execute_cdc_cluster_{id} ─► [per-event tasks] ─► end_cdc_cluster_{id}
                            └──────────────────────────────────────────────────► end_cdc_cluster_{id}
```

Per event (typical): raw → quality_raw → clean → quality_clean → dlq → [stability, latency, missing_events] → end.
Every metric task runs after the DLQ: stability and latency read the raw and clean
layers that the DLQ writes to, so running them alongside it would race its writes.
Every operator on that path takes the **same** `pool`.

`cluster_id` is the event name for dedicated clusters (`case`, `email_message`)
or `"0"` / `"1"` / … for the event job pool. Pool name is always
`salesforce_cdc_cluster_{cluster_id}`.

---

## When adding a new cluster

Always go through `build_cluster_lineage(cluster_id, events)` — it already
calls `ensure_lineage_pool`. Do **not** create `execute_cdc_cluster_*` (or any
lineage task) without `pool=`.

### Dedicated cluster (one heavy event on its own Databricks cluster)

1. Add the event key to `DEDICATED_CLUSTER_EVENTS` (must match `events_config`).
2. Confirm the DAG loop still calls `build_cluster_lineage(event, [event])`.
3. Register the Airflow pool in `astro/local_pools.json` (**required** even
   though parse-time `Pool.create_or_update_pool` exists — local Astro has no
   metadata DB at first parse):

```json
{
  "pool_name": "salesforce_cdc_cluster_<event>",
  "slots": 1,
  "description": "One active hour at a time for salesforce_cdc <Event> lineage."
}
```

4. Pass `pool` into every new operator you add on that lineage (`create_sst_task`,
   placeholders, execute cluster). The post-clean lineage is declarative: add an
   entry to `POST_CLEAN_STAGES` rather than a new builder function, and
   `wire_task_stages` threads `pool` through for you.
5. Keep `slots: 1`. Do not raise slots to "go faster" — that reintroduces
   overlapping hours of the same cluster.

### Extra pooled Databricks cluster (more event-job-pool members)

1. Bump `NUMBER_OF_POOLED_CLUSTERS` if you truly need another Spark cluster
   for leftover events (not dedicated).
2. Add `salesforce_cdc_cluster_{n}` to `astro/local_pools.json` with `slots: 1`
   for each new index (`2`, `3`, …).
3. `build_cluster_lineage(str(i), pool_events)` already creates the pool at
   parse; the JSON entry is still required for local Airflow.

### New event that stays in the event job pool

No new Airflow pool. Existing `salesforce_cdc_cluster_0` / `_1` (and any extra
indices) already serialize those clusters. Do not put a leftover event on a
dedicated cluster "for convenience" without adding `DEDICATED_CLUSTER_EVENTS`
**and** `local_pools.json`.

---

## Checklist (every cluster change)

- [ ] Lineage built only via `build_cluster_lineage` (or copies its pool + gate + execute + end wiring).
- [ ] `ensure_lineage_pool(cluster_id)` runs; name is `salesforce_cdc_cluster_{cluster_id}`.
- [ ] **Every** task on the lineage has `pool=` (gate, execute, raw, quality, clean, metrics, dlq, end).
- [ ] Matching entry in `astro/local_pools.json` with **`slots: 1`**.
- [ ] Execute still has `depends_on_past=True` and `wait_for_downstream=True`.
- [ ] `wait_previous_lineage_{id}` still wires to both execute and `end_cdc_cluster_{id}`.
- [ ] `max_active_runs` stays 24 unless you are deliberately changing catch-up window (document why).
- [ ] Databricks `cluster_name` still includes `{cluster_id}` (digit-less ids like `case` must not collide on job name).

---

## Do not

- Share one Airflow pool across two `cluster_id`s.
- Give a lineage `slots > 1`.
- Drop `pool=` on a new task "just this once".
- Rely only on `max_active_runs` or only on `depends_on_past` — both miss
  overlapping hours under catchup without the 1-slot pool.
- Add a dedicated `execute_cdc_cluster_*` that bypasses `build_cluster_lineage`
  without copying pool + previous-lineage gate.
