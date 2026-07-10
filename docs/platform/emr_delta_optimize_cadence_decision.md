# Decision: EMR Delta OPTIMIZE cadence

- **Status:** Accepted
- **Date:** 2026-07-09
- **PR:** [#26029](https://github.com/quintoandar/bi-etl-ejuice/pull/26029)
- **Related code:** `packages/bietlejuice-core/src/bietlejuice/base/airflow/task_creators/optimize_delta_table_task_creator.py`, `dags/cross/base/spark_jobs/optimize_delta_table.py`, `packages/bietlejuice-core/src/bietlejuice/base/delta/maintenance_state.py`

## Context

Every DAG Builder table with maintenance enabled runs `OPTIMIZE` (compaction +
optional `ZORDER BY`) and `VACUUM` on the same daily cadence, gated by a single
S3 maintenance marker per execution date. This was tuned for Databricks, where
`OPTIMIZE` benefits from Databricks-native compaction (bin-packing, file-size
heuristics, optional Photon) and is comparatively cheap.

On EMR, tables run on plain Delta Lake OSS: `OPTIMIZE` is a full,
unaccelerated Spark shuffle/rewrite job with none of the Databricks-side
optimizations. As EMR adoption grew, `OPTIMIZE` became one of the largest
line items in EMR compute cost for tables that don't strictly need the
clustering benefit `ZORDER` provides — daily `OPTIMIZE` was running
unconditionally regardless of whether it was buying anything.

## Decision

1. **Default `run_optimize` off on EMR, unless the table has `ZORDER` columns
   configured.** Without `ZORDER`, `OPTIMIZE`'s only job is bin-packing; on
   Delta OSS that benefit is small relative to its cost, so it's disabled by
   default (`VACUUM` is unaffected and keeps running daily). Databricks
   defaults are unchanged (`run_optimize=true`, daily) — this is an EMR-only
   behavior change.
2. **When EMR + `ZORDER` is configured, run `OPTIMIZE` weekly instead of
   daily** (`optimize_frequency_days=7`), tracked via a new, independent S3
   cursor (`optimize_cursor.json`) decoupled from the existing daily
   maintenance marker — so `VACUUM` keeps its own daily cadence even on weeks
   where `OPTIMIZE` is skipped.
3. **The weekly default only applies to full-table `OPTIMIZE`.** Whenever the
   run is partition-filtered — `TRANSACTIONAL`-layer tables by default, or any
   table with `incremental_optimize` enabled (table- or workflow-level) —
   `optimize_frequency_days` is forced back to `1` (daily), regardless of
   `ZORDER`. See [Partition-filter gap](#partition-filter-gap-caught-before-ship) below for why.
4. **Add write-side small-file defaults to the EMR cluster `spark_conf`**
   (`prod_conf.yml` / `forno_conf.yml`): `spark.sql.files.maxPartitionBytes=256MB`
   and AQE (`adaptive.enabled`, `adaptive.coalescePartitions.enabled`,
   `adaptive.advisoryPartitionSizeInBytes=256MB`). These reduce the number of
   small files produced at write time, lowering the cost of whatever
   `OPTIMIZE` still needs to do — independent of the cadence change, and
   applicable to every EMR table regardless of maintenance configuration.
5. **Explicit overrides always win.** `run_optimize` and
   `optimize_frequency_days` can still be set per table
   (`tables_customization`) or per workflow (`workflow_args`), on either
   engine, taking precedence over every default in this decision.

### Decision matrix

| Engine | ZORDER configured? | `apply_partition_filter`? | `run_optimize` default | `optimize_frequency_days` default | What actually runs |
|---|---|---|---|---|---|
| Databricks | any | any | `true` | `1` | OPTIMIZE + VACUUM **every day** (unchanged, historical behavior) |
| Databricks | any | any, with explicit override (e.g. `optimize_frequency_days: 7`) | per override | per override | OPTIMIZE gated by cursor to that cadence; VACUUM still daily |
| EMR | No | any | `false` | `1` (moot — OPTIMIZE doesn't run) | **No OPTIMIZE at all**; VACUUM still runs daily |
| EMR | Yes | `false` (full-table OPTIMIZE) | `true` | `7` | OPTIMIZE **once a week** (cursor-gated); VACUUM still runs daily |
| EMR | Yes | `true` (`TRANSACTIONAL` layer by default, or `incremental_optimize`) | `true` | `1` | OPTIMIZE **every day**, scoped to that day's partitions; VACUUM still daily |
| EMR | any | any, with explicit `run_optimize: false` | `false` | n/a | No OPTIMIZE, regardless of ZORDER; VACUUM still runs daily |
| EMR | any | any, with explicit `run_optimize: true` (no frequency override) | `true` | `1` | OPTIMIZE **every day** (explicit override wins, no weekly cap) |
| EMR | any | any, with explicit `optimize_frequency_days: N` | per override | `N` | OPTIMIZE gated to every `N` days; VACUUM still daily |

**Key takeaways:**
- `VACUUM` is never affected by any of this — it runs daily on both engines,
  gated only by its own `run_vacuum` flag and the existing daily marker.
- Databricks is untouched by default — daily OPTIMIZE, same as before this
  change.
- EMR is the only engine whose default flips — OPTIMIZE off unless `ZORDER`
  is configured, in which case it's on but capped to weekly *only if*
  OPTIMIZE runs full-table.
- Explicit config always overrides the engine-aware default, on either
  engine.

## Partition-filter gap (caught before ship)

`OPTIMIZE`'s `WHERE` clause (`_resolve_partition_predicate` in
`optimize_delta_table.py`) is scoped to the **current run's**
`load_start_date`/`load_end_date` — it has no notion of "everything since the
last actual `OPTIMIZE`". `apply_partition_filter` defaults to `true` for
`LayerEnum.TRANSACTIONAL` tables (opt out via `optimize_partition_filter:
false`) and for any table with `incremental_optimize` enabled.

If the weekly default (`optimize_frequency_days=7`) applied unconditionally,
a partition-filtered table would only get `OPTIMIZE`'d on the one day out of
seven the cadence happens to allow it to run — and that run's `WHERE` clause
covers only *that day's* partition. **The other six days' partitions would
never be touched by `OPTIMIZE` again**, since no later run's predicate ever
looks backward.

Two fixes were considered:

- **Option A — always daily with `ZORDER`:** Drop the weekly-cadence default
  entirely whenever `ZORDER` is configured, regardless of partition
  filtering. Simplest, but it also reverts full-table `OPTIMIZE`+`ZORDER`
  tables to daily — the exact expensive case this change set out to fix.
- **Option B — cadence conditional on `apply_partition_filter` (chosen):**
  Keep the weekly default only for full-table `OPTIMIZE`. Force
  `optimize_frequency_days=1` whenever `apply_partition_filter` is `true`.
  Partition-filtered `OPTIMIZE` is already bounded to a single day's data, so
  it's cheap regardless of cadence — daily execution there costs little and
  closes the coverage gap. This preserves the cost reduction where it
  actually matters (full-table `OPTIMIZE`) without reintroducing it where it
  would silently corrupt clustering guarantees.

A third option (widen the predicate window to cover every day since the last
successful `OPTIMIZE`, so a weekly run retroactively covers the skipped days)
was discussed but rejected as unnecessary complexity — Option B gets the same
outcome (every partition still gets `OPTIMIZE`'d) with no need to track a
per-table "days since last run" window in the predicate logic itself.

**Option B was chosen.** Implemented via a new
`_resolve_apply_partition_filter` helper computed before
`_resolve_run_optimize_and_frequency`, so the frequency default can consult
it directly.

## Consequences

- On EMR, tables with no `ZORDER` stop running `OPTIMIZE` entirely by
  default. Anyone who actually relies on compaction alone (no clustering
  need) should set `run_optimize: true` explicitly if the small-file defaults
  (see below) aren't sufficient on their own.
- On EMR, full-table `OPTIMIZE`+`ZORDER` tables move from daily to weekly —
  clustering quality between runs degrades slightly (more unclustered writes
  accumulate before the next `OPTIMIZE`), traded for a ~7x reduction in
  `OPTIMIZE` compute cost on those tables.
- Partition-filtered/incremental `OPTIMIZE`+`ZORDER` tables (e.g.
  `TRANSACTIONAL`-layer tables, `dw_agent`'s `fact_visit_agent_performance`)
  see no cadence change — they stay daily, as before this feature, avoiding a
  regression that would have gone unnoticed until a downstream query against
  a stale-clustered day-partition became visibly slow.
- The new `optimize_cursor.json` marker is independent of the pre-existing
  daily maintenance marker; the first `OPTIMIZE` run after deploying this on
  an EMR+`ZORDER` table always fires (no cursor yet), then falls onto the
  weekly/daily cadence from that point on.
- `maxPartitionBytes`/AQE cluster defaults apply to every EMR Spark job, not
  just maintenance — they reduce small-file counts at the source, which is
  strictly additive to whatever cadence `OPTIMIZE` ends up running on.
