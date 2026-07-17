# amplitude_optimization — clean v2 twin ops runbook

Manual twin for unlocking `amplitude_new` clean throughput. Code lives under
`dags/growth/amplitude_optimization/`.

## What this DAG does

| Item | Value |
|------|--------|
| Schedule | `null` (manual only) |
| Datasets | none (`datasets = None`) |
| Reads | `datalake_amplitude_new_raw.events` (Delta only) |
| Writes | `datalake_amplitude_events_v2_clean.events` |
| Partitions | `id_app, year, month, day` (no `event_type`; no ZORDER) |
| Load window | **single day** by default (`load_start = load_end = D`) |
| Optimize / vacuum | **off** (load layout from optimizeWrite is enough for experiments) |
| Cluster | `consolidation_l_memory_cluster`, 5× **`r7gd.4xlarge`** workers (NVMe), Spot, driver `r7g.xlarge` |
| Coverage | dates **≥ 2026-06-07** only |

Production `amplitude_new` and the consumer VIEW `datalake_amplitude_clean.events` stay on v1 until cutover.

## Findings so far (do not ignore)

1. **Partition change ≠ wall-clock win.** Twin load for Jul 13–14 (~126M rows) was ~1h58m vs prod clean ~2h17m. Layout improved a lot (995 zstd files / 44 GiB vs v1 ~19k files / 113 GiB for the same rows), but EBS shuffle spill / iowait dominated.
2. **OPTIMIZE + ZORDER as first configured was harmful.** It re-encoded zstd → snappy and inflated live v2 from ~44 GiB to ~1.2 TiB. Keep `run_optimize` / `run_vacuum` **false** on the twin until a safe codec + `maxFileSize` recipe is proven.
3. **Raw Delta does not rewrite D−1.** All 35 large raw commits since Jun 14 write **exactly one** calendar day. The prod clean `[D−1, D]` window re-shuffles ~half the bytes with no raw update behind it. Twin defaults to **single-day**; use conf overrides only when you intentionally need a multi-day repair.

## Control run — v1 partitions via `__validation` (temporary)

**Goal:** measure NVMe + single-day with production partition scheme
`[id_app, event_type, year, month, day]` without writing into the live twin
table (and without confounding the prior no-`event_type` layout).

**Current branch state (revert after measurement):**

| Item | Value |
|------|--------|
| Declaration partitions | `id_app, event_type, year, month, day` (match `amplitude_new`) |
| Main twin cluster | EBS preset workers (`r7g.4xlarge` via `consolidation_l_memory_cluster`; no redundant `node_type_id`) |
| Validation cluster | NVMe `r7gd.4xlarge` ×5 (control experiment) |
| Validation write target | `cluster_validation.datalake_amplitude_events_v2_clean___events` |
| Validation S3 | `s3a://{datalake_bucket}/validation/cluster_validation/datalake_amplitude_events_v2_clean/` |

1. Deploy this branch (or sync local Airflow) so `bietlejuice.amplitude_optimization__validation` exists.
2. Trigger **only** `bietlejuice.amplitude_optimization__validation` with a single-day conf (e.g. Jul 14).
3. Compare wall-clock / iowait / file layout to the prior Jul-14 twin run (~29m, no `event_type` partition).
4. Revert declaration partitions to `[id_app, year, month, day]`, restore twin cluster `node_type_id: r7gd.4xlarge`, and remove the `validation:` block (or keep validation only if still useful).

Do **not** trigger `bietlejuice.amplitude_optimization` while partitions include `event_type` — that would overwrite go-forward days on `datalake_amplitude_events_v2_clean` with the v1 partition layout.

## Manual trigger confs

### Daily / prove (default — matches declaration)

After `amplitude_new` succeeds for day `D`:

```json
{"load_start_date": "D", "load_end_date": "D"}
```

Example for Jul 14:

```json
{"load_start_date": "2026-07-14", "load_end_date": "2026-07-14"}
```

If you omit conf and set logical / data interval to `D`, declaration defaults are the same single day.

### Repair / multi-day (override only)

Force a 2-day window when repairing history (e.g. overwrite bad OPTIMIZE output):

```json
{"load_start_date": "2026-07-13", "load_end_date": "2026-07-14"}
```

Prefer **two sequential single-day runs** when measuring wall-clock so each run matches what raw actually wrote.

### Repair current snappy v2 layout (Jul 13 then Jul 14)

```json
{"load_start_date": "2026-07-13", "load_end_date": "2026-07-13"}
```

then

```json
{"load_start_date": "2026-07-14", "load_end_date": "2026-07-14"}
```

## Success criteria (NVMe + single-day)

Compare especially a Jul-14 single-day twin run vs prior twin (2-day on EBS) and vs prod clean:

- `load-clean-events` wall-clock well under prior ~1h58m for two days (expect ~half bytes + faster spill disk)
- Metrics: lower **iowait**; spill not stuck on a single EBS volume
- S3: zstd, tens-of-MB files, ~20 GiB/day — **not** TiB snappy
- Row parity vs v1 for that day (~62M for Jul 14)

Optional parity SQL:

```sql
SELECT 'v1' AS src, COUNT(*) AS n
FROM quintoandar_prod.datalake_amplitude_events_clean.events
WHERE year = 2026 AND month = 7 AND day = 14
UNION ALL
SELECT 'v2', COUNT(*)
FROM quintoandar_prod.datalake_amplitude_events_v2_clean.events
WHERE year = 2026 AND month = 7 AND day = 14;
```

## Backfill from June (`backfill-from-june`)

For each date `D` from `2026-06-07` through yesterday:

1. Confirm `bietlejuice.amplitude_new` succeeded for `D` (raw + clean).
2. Trigger `bietlejuice.amplitude_optimization` with single-day conf for `D`.
3. Wait for `load-clean-events` to succeed (optimize is disabled).
4. Optional parity check (same SQL as above with `D`).

Prefer proving NVMe + single-day on 1–2 recent days before walking history.

## Prove daily (`prove-daily`)

After a few twin runs:

- Twin wall-clock << prod `load-clean-events` for the **same single day**
- Lower iowait / healthier CPU than the EBS twin run
- Row counts match for the same `D`
- v2 files stay zstd and well-sized (no accidental OPTIMIZE inflation)

Do **not** cut over until this holds for several days.

## Next experiments (only if still slow)

- Disable `spark.databricks.delta.optimizeWrite` on the twin (isolate shuffle cost)
- Prod candidates after a strong win: NVMe workers and/or single-day clean window on `amplitude_new` (separate change; prod stays 2-day until proven)

## Cutover (`declaration-cutover`) — do only after prove

Single brief maintenance window:

1. Pause `bietlejuice.amplitude_new` in Airflow.
2. Update [`amplitude_new_declaration.yml`](../../dags/growth/amplitude_new/amplitude_new_declaration.yml) toward the proven twin layout (partitions without `event_type`; **revisit** optimize/ZORDER only with zstd + capped file size; strongly consider single-day `load_*` defaults).
3. Align cluster with proven twin (e.g. `r7gd` workers if NVMe was the win).
4. `make create-dag-files dag_name=amplitude_new` and merge.
5. Swap the consumer view:

```sql
CREATE OR REPLACE VIEW quintoandar_prod.datalake_amplitude_clean.events
AS SELECT * FROM quintoandar_prod.datalake_amplitude_events_v2_clean.events;
```

6. Resume `amplitude_new` and trigger one manual day.
7. Retire / delete `amplitude_optimization` once prod is stable.

**Rollback:** repoint the VIEW to `datalake_amplitude_events_clean.events` and revert the declaration.

## Post-cutover monitor (`validate-monitor`)

For one week:

- `load-clean-events` duration and timeout risk
- Worker CPU busy / iowait pattern
- v2 `numFiles` / size growth (`DESCRIBE DETAIL` + S3)
- Consumer queries via `datalake_amplitude_clean.events` unchanged

Then archive/drop the old physical v1 table when safe.
