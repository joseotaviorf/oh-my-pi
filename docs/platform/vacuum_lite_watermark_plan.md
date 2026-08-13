# Re-enable VACUUM LITE after a full vacuum (watermark bootstrap)

## Context

`DPLT-1745` (`02816c02e9`, #27563) made `vacuum_lite: true` the repo default and added a
fallback: any failure of `VACUUM <t> LITE` re-runs the table as full `VACUUM`. That keeps jobs
green but never delivers the performance win on mature tables, because of a Delta defect.

Verified in `delta-spark_2.12-3.3.1` (the jar in `~/.ivy2/cache`, matching the pinned runtime)
**and unchanged on `delta-io/delta` master**:

```scala
// VacuumCommand.gc — 3.3.1 line 286 / master line ~236
val latestCommitVersionOutsideOfRetentionWindowOpt: Option[Long] =
  if (vacuumType == VacuumType.LITE) { ...compute... } else { None }

// unconditional, runs for FULL too — 3.3.1 line 483 / master line 409
LastVacuumInfo.persistLastVacuumInfo(
  LastVacuumInfo(latestCommitVersionOutsideOfRetentionWindowOpt), deltaLog)

// LITE eligibility gate — 3.3.1 line 530 / master line 456
if (earliestCommitVersion != 0 &&
  latestCommitVersionOutsideOfRetentionWindowAsOfLastVacuumOpt
    .forall(_ < earliestCommitVersion)) {
  throw DeltaErrors.deltaCannotVacuumLite()
}
```

Consequences:

- `earliestCommitVersion != 0` is true for any table whose log has been cleaned
  (`delta.logRetentionDuration`, default 30 days) — i.e. nearly every mature production table.
- The watermark lives in `_delta_log/_last_vacuum_info`. Only a **successful LITE** writes a real
  value; a FULL writes `None`. `None.forall(...)` is `true` in Scala, so a missing-or-null
  watermark satisfies the gate condition.
- Therefore the fallback is a closed loop: LITE fails -> FULL runs -> FULL **wipes** the
  watermark to `None` -> next LITE fails identically. It is also a ratchet: one FULL from any
  source permanently disqualifies a table from LITE while its log stays truncated.

Not fixed upstream, so there is no version to wait for and no EMR bump that resolves it. EMR
ships an embedded Delta and upgrading is out of our control regardless.

The error message (`"VACUUM LITE cannot delete all eligible files as some files are not
referenced by the Delta log. Please run VACUUM FULL."`) is misleading: it suggests orphaned
files in storage, but the gate never inspects storage. It is purely commit-history bookkeeping.

## Goal

After a successful fallback full vacuum, write a valid watermark so the *next* scheduled run can
actually use LITE. This makes the existing fallback genuinely self-healing and makes the
`DPLT-1745` default flip pay off, instead of costing a failed statement per table per run.

Non-goals: changing the `vacuum_lite` default (stays `true`), changing retention semantics,
touching `vacuum_table` (explicit `vacuum_lite: false` opt-out must remain a plain full vacuum),
recreating any table, backfilling watermarks for tables not currently running maintenance.

## Why writing the watermark is semantically honest

The full vacuum we just ran was **exhaustive**: it listed the whole table prefix and deleted
every file not referenced by the snapshot and older than the retention horizon. So at that
moment, "everything eligible at or before version N has been cleaned" is a fact for any N whose
commits are older than the retention horizon.

### Choice of N — use `earliestCommitVersion`

`N` must satisfy `N >= earliestCommitVersion` or the gate still throws (`N < earliest` -> throw).
So the smallest legal value is exactly `earliestCommitVersion`.

That value is also the *safest*, for two reasons:

1. The next LITE computes `eligibleStartCommitVersion = min(currentVersion, N + 1)`
   (`3.3.1:538-541`, `min` imported at the top of the file). A smaller `N` means a **wider**
   rescan range, so it can only discover more tombstones, never fewer.
2. The one thing a start of `N + 1` skips is tombstones recorded *in commit N itself*. That is
   harmless here: `earliestCommitVersion` is the oldest surviving commit of a truncated log, so
   it is necessarily older than `logRetentionDuration` (30d) and far outside the file retention
   window (48h) — meaning our exhaustive FULL already deleted those files.

Deleting a file that is still needed is not possible via this path: the outer `diff` does a
`leftanti` against `validFiles` (current snapshot) and filters
`modificationTime < deleteBeforeTimestamp`, so a re-added file is excluded.

## Approach

All code changes are in
`packages/bietlejuice-runtime/src/bietlejuice/loaders/delta_loader.py`.

### 1. Capture the canonical file format first — do not guess it

Before writing any writer code, produce the file with Delta itself and record the exact bytes:
create a fresh local Delta table (log still contains commit `0`, so LITE is eligible), run a
successful `VACUUM <t> LITE`, then read `_delta_log/_last_vacuum_info`.

Expected shape, to be **confirmed** rather than assumed:

```json
{"latestCommitVersionOutsideOfRetentionWindow":10}
```

`LastVacuumInfo` is a single-field case class with
`@JsonDeserialize(contentAs = classOf[java.lang.Long])` on an `Option[Long]`, so a bare integer
is correct. Our writer must emit byte-compatible output. Record the observed string in a test
constant so a future Delta change that alters the shape fails loudly in CI.

### 2. Module-level constants

Beside `_VACUUM_LITE_NOT_APPLICABLE_ERROR_CLASS`:

```python
# Delta stores the "already cleaned up to this version" watermark here. A full VACUUM
# persists null into it, which permanently disqualifies the table from LITE; we rewrite it
# after a successful full vacuum so the next run can use LITE again.
# Verified against delta-spark 3.3.1 and delta-io/delta master (unchanged).
_LAST_VACUUM_INFO_FILE_NAME = "_last_vacuum_info"
_DELTA_LOG_DIR_NAME = "_delta_log"
_COMMIT_FILE_RE = re.compile(r"^(\d{20})\.json$")
_VACUUM_LITE_WATERMARK_CONF = "spark.bietlejuice.delta.vacuumLiteWatermarkBootstrap"
```

`re` is already imported (line 1).

### 3. Resolve the table's log directory

```python
def _delta_log_dir(self, table_name: str) -> str:
    table_name = _check_identifier_safety(table_name)
    quoted_table = _quote_sql_table_name(table_name)
    location = self.spark.sql(f"DESCRIBE DETAIL {quoted_table}").select("location").first()[0]
    return f"{location.rstrip('/')}/{_DELTA_LOG_DIR_NAME}"
```

Uses `DESCRIBE DETAIL` rather than a config-derived path so it works for managed and external
tables and for both Databricks and EMR/Glue catalogs.

### 4. Read `earliestCommitVersion` and write the watermark

Both via the Hadoop `FileSystem` through py4j, so the same code works for `s3://`, `s3a://` and
local paths, and inherits the cluster's credentials. Do **not** use boto3 (would break on
non-S3 and duplicate credential handling), and do **not** call Delta's Scala
`LastVacuumInfo.persistLastVacuumInfo` via py4j (constructing a Scala `Option` across py4j is
brittle across Scala versions — the exact coupling we are trying to avoid).

```python
def _persist_vacuum_lite_watermark(self, table_name: str) -> None:
    """Rewrite `_last_vacuum_info` so the next run can use VACUUM LITE.

    Delta persists a null watermark on full vacuums, which permanently disqualifies the
    table from LITE (DELTA_CANNOT_VACUUM_LITE). The full vacuum that just completed was
    exhaustive, so declaring "already cleaned up to <earliest retained commit>" is true.

    Best-effort by design: this is an optimisation for the *next* run, so any failure is
    logged and swallowed. The vacuum itself has already succeeded at this point.
    """
```

Body outline:

1. Return early unless the conf flag is enabled (step 5).
2. `log_dir = self._delta_log_dir(table_name)`.
3. Get `fs` + `Path` via `self.spark._jvm` / `self.spark._jsc.hadoopConfiguration()`.
4. `fs.listStatus(path)`; collect versions matching `_COMMIT_FILE_RE`; `min(...)`. If no commit
   files matched, log a warning and return without writing.
5. Write `{"latestCommitVersionOutsideOfRetentionWindow":<N>}` (no trailing newline unless step 1
   shows otherwise) to `<log_dir>/_last_vacuum_info` with `fs.create(out_path, True)`
   (overwrite), passing a `bytearray` (py4j maps it to `byte[]`), then `close()` in a `finally`.
6. `logger.info` the table and the version written.

The whole body is wrapped so nothing escapes:

```python
    try:
        ...
    except Exception as error:  # noqa: BLE001 - optimisation only, never fail the vacuum
        logger.warning(
            f"Could not persist vacuum lite watermark for table {table_name} "
            f"({type(error).__name__}: {str(error)[:500]}); the next run will fall back "
            f"to full vacuum again."
        )
```

### 5. Feature flag: Airflow Variable, default off

Toggled by the **`vacuum_lite_watermark_enabled` Airflow Variable** so it can be flipped from
the Airflow UI with no deploy. The flag is consumed on the *cluster*, which has no access to
the Airflow metastore, so it travels: Variable -> task creator -> spark job CLI -> loader.

Read as a Jinja template rendered at task runtime, never via `Variable.get()` at module level,
which would hit the metadata DB on every scheduler DAG parse. Matches the existing convention
(`sst/airflow/common/common.py:31` uses `{{ var.value.get('glue_assume_role_arn', '') }}`).

`optimize_delta_table_task_creator.py`, module level:

```python
_VACUUM_LITE_WATERMARK_TEMPLATE = (
    "{{ var.value.get('vacuum_lite_watermark_enabled', 'false') }}"
)
```

appended in `_build_optimize_job_parameters` as `--vacuum-lite-watermark <template>`.

`optimize_delta_table.py` parses it fail-safe -- only the exact string `"true"` enables it, so
an unset Variable, a typo, or an unrendered template leaves behaviour unchanged:

```python
bootstrap_lite_watermark = args.vacuum_lite_watermark.strip().lower() == "true"
```

then threads it through `job_args` into `run_job(..., bootstrap_lite_watermark)` and on to
`loader.vacuum_lite_table(..., bootstrap_watermark=...)`.

### 6. Hook into the fallback path only

In `vacuum_lite_table`'s `except` branch, after the full vacuum returns successfully:

```python
            self._run_full_vacuum(table_name, retention_hours)
            self._persist_vacuum_lite_watermark(table_name)
            return
```

Placement matters: after `_run_full_vacuum`, so a failed full vacuum propagates *before* we
claim anything was cleaned. Not in `vacuum_table` — a table with `vacuum_lite: false` never
issues LITE, so the watermark would be inert, and keeping it out preserves the smallest blast
radius.

## Tests

`packages/bietlejuice-runtime/test/unit/loaders/test_delta_loader.py`, following the existing
`mock_spark_context` (autouse, lines 64-70) and `mock.call` assertion style:

1. `test_vacuum_lite_fallback_persists_watermark_when_enabled` — LITE raises, flag on; assert
   full vacuum ran **and** the watermark write happened with the minimum commit version.
2. `test_vacuum_lite_fallback_skips_watermark_when_disabled` — flag off (default); assert no
   `_last_vacuum_info` write and no `DESCRIBE DETAIL`.
3. `test_watermark_failure_does_not_fail_vacuum` — watermark helper raises; assert
   `vacuum_lite_table` still returns normally (this is the guardrail that matters most).
4. `test_watermark_not_written_when_full_vacuum_fails` — LITE raises, then full vacuum raises;
   assert the error propagates and no watermark write occurred.
5. `test_vacuum_table_does_not_persist_watermark` — the `vacuum_lite: false` path stays clean.
6. `test_watermark_payload_matches_delta_format` — pins the exact JSON string captured in step 1.

Existing `test_vacuum_table`, `test_vacuum_lite_table`, both parametrized fallback cases, the
propagation test and the two malicious-name tests must keep passing untouched.

## Verification — the e2e proof that matters

Unit tests with mocks cannot prove the loop is broken; only real Delta can. Local script,
`/tmp/vacuum_lite_watermark_probe.py`, run with the Delta jars on the driver classpath:

```bash
cd packages/bietlejuice-runtime && \
DBR_PY=$(uv run --project envs/dbr-16-4 python -c "import sys; print(sys.executable)") && \
IVY=~/.ivy2/cache/io.delta && \
PYSPARK_SUBMIT_ARGS="--jars $IVY/delta-spark_2.12/jars/delta-spark_2.12-3.3.1.jar,$IVY/delta-storage/jars/delta-storage-3.3.1.jar pyspark-shell" \
PYSPARK_PYTHON=$DBR_PY PYSPARK_DRIVER_PYTHON=$DBR_PY PYTHONPATH=src \
uv run --project envs/dbr-16-4 python /tmp/vacuum_lite_watermark_probe.py
```

(The earlier probe in this repo failed with `ClassNotFoundException: DeltaCatalog` precisely
because `--jars` was missing; that is what `PYSPARK_SUBMIT_ARGS` fixes.)

Script stages:

1. Create a Delta table and commit ~12 times, so Delta writes a checkpoint at version 10.
2. **Simulate log cleanup faithfully**: delete commit json files `0..9` from `_delta_log` while
   keeping `10.checkpoint.parquet` and `10.json` onward — this is exactly what Delta's own log
   cleanup leaves behind, and it makes `earliestCommitVersion == 10 != 0`.
3. Confirm the broken baseline: with the flag **off**, `vacuum_lite_table` logs the
   `DELTA_CANNOT_VACUUM_LITE` warning and falls back; then assert
   `_last_vacuum_info` contains a null watermark. Run it a second time and assert it fails
   *again* — this is the loop, reproduced.
4. Turn the flag **on** and repeat: assert the warning appears once, the fallback runs, and
   `_last_vacuum_info` now contains `{"latestCommitVersionOutsideOfRetentionWindow":10}`.
5. **The money assertion**: churn the table again, then call `vacuum_lite_table` once more and
   assert the LITE statement **succeeded** — no fallback warning in the captured logs — and that
   the parquet file count strictly decreased, i.e. LITE actually deleted files.
6. Assert the table still reads its expected row count, then clean up the temp warehouse and
   delete the probe script.

Pass condition: stage 3 reproduces the loop, stage 5 shows LITE succeeding and deleting. Without
both, the change is not proven and must not ship.

Also run the existing suites, which must stay green:

```bash
cd packages/bietlejuice-runtime && \
DBR_PY=$(uv run --project envs/dbr-16-4 python -c "import sys; print(sys.executable)") && \
PYSPARK_PYTHON=$DBR_PY PYSPARK_DRIVER_PYTHON=$DBR_PY \
uv run --project envs/dbr-16-4 pytest test/unit/loaders/test_delta_loader.py -W ignore::DeprecationWarning

cd packages/bietlejuice-runtime && \
DBR_PY=$(uv run --project envs/dbr-16-4 python -c "import sys; print(sys.executable)") && \
PYSPARK_PYTHON=$DBR_PY PYSPARK_DRIVER_PYTHON=$DBR_PY PYTHONPATH=src:../.. \
uv run --project envs/dbr-16-4 pytest test/dags/cross/base/spark_jobs/test_optimize_delta_table.py -W ignore::DeprecationWarning
```

## Risks

- **Undocumented Delta internal.** `_last_vacuum_info` is not public API. Mitigated by the
  degradation path: if a future Delta rejects our file, `getLastVacuumInfo` only catches
  `FileNotFoundException`, so a parse error propagates, `VACUUM LITE` fails, and the **existing**
  fallback runs a full vacuum. Worst case is today's behaviour, never data loss. Test 6 pins the
  format so a change is caught in CI rather than in production.
- **Writing into `_delta_log`.** Only a side file, never a commit; `persistLastVacuumInfo` itself
  uses a plain overwrite (`3.3.1:966`), so we are not bypassing the commit protocol. Requires
  the same write permission the job already holds on the table.
- **Concurrency.** Overwrite races are benign (both writers produce a valid version) and the job
  processes each table once, on one thread (`ThreadPool` + `apply_async`, one task per table).
- **Wrong `N` too high** would make LITE skip tombstones. Avoided by construction: we use the
  minimum retained version, the most conservative legal value.
- **Old runtimes** (Delta < 3.3, DBR 10.4/12.2/13.3) ignore the file entirely — dead weight, no
  behaviour change, and those tables keep falling back on the LITE parse error as they do today.

## Rollout

1. Merge with the flag defaulting to `false` — inert.
2. Enable via `spark_conf` on **one** DAG, ideally one with `data_quality`-style small tables,
   and confirm across two scheduled runs: run 1 logs the fallback and writes the watermark, run 2
   shows no fallback warning and a real LITE.
3. Widen to more DAGs, then flip the default to `true` in a follow-up PR.
4. Only then is the `DPLT-1745` default flip actually delivering; revisit whether any table still
   needs `vacuum_lite: false`.

## Separate deliverable — upstream issue

Open an issue on `delta-io/delta`: FULL vacuum persists `LastVacuumInfo(None)`, wiping the
watermark and permanently disqualifying a log-truncated table from LITE. Include the three code
citations above (master line numbers), the misleading error-message text, and the observation
that the symptom is masked in most deployments by callers falling back to FULL. Propose that FULL
persist the version it effectively cleaned rather than `None`.

## Out of scope

- Changing the `vacuum_lite` default (stays `true`).
- Backfilling `_last_vacuum_info` for tables outside the maintenance DAGs.
- `delta.logRetentionDuration` tuning — does not help already-truncated tables, since the commits
  are already gone.
- Recycling the EMR clusters still running the pre-`02816c02e9` wheel; that is operational and
  tracked separately.

## Implementation results (executed)

All stages of this plan were carried out. Tests: **59** loader + **32** spark job + **685**
core, all passing; `ruff check` and `ruff format` clean on all five changed files.

### Empirical findings that corrected the plan

1. **The null watermark serialises as `{}`, not `null`.** Jackson omits the field entirely when
   the Scala `Option` is `None`, so a full vacuum leaves `{}`. Either shape yields `None` from
   `getLastVacuumInfo().flatMap(...)`, so the gate still throws -- but an assertion looking for
   the literal `null` fails. The unit test asserts on the parsed value, not the raw string.
2. **The payload has a trailing newline** -- `b'{"latestCommitVersionOutsideOfRetentionWindow":5}\n'`,
   50 bytes, from `LogStore.write(path, Iterator.single(json))`. Captured from a real successful
   LITE run rather than guessed, per step 1.
3. **`DELTA_CANNOT_VACUUM_LITE` surfaces as a raw `Py4JJavaError`**, confirming why the original
   DPLT-1745 fallback catches `Exception` broadly instead of matching a Delta exception type.
4. **The probe needs `--driver-class-path`, not `--jars`.** With `--jars`, the driver's file
   server transfer collided with the RPC channel and `SparkContext` init died with
   `IllegalArgumentException: Too large frame: 5785721462337832960` (`0x504B0304` = the `PK`
   ZIP magic, i.e. a jar arriving on an RPC channel). In `local[N]` the executor shares the
   driver JVM, so the driver classpath suffices.
5. **`BaseSparkContext` creates the SparkContext at import time** (`base_spark.py:149`), so any
   script importing `DeltaLoader` must supply all Spark/Delta settings via
   `PYSPARK_SUBMIT_ARGS`; building a `SparkSession` first yields a second context.

### E2E probe output

```
B) removed 20 log files; earliestCommitVersion = 10
C) flag OFF: run1 fell_back=True  watermark={}
   flag OFF: run2 fell_back=True  watermark={}
D) flag ON:  fell_back=True  watermark={"latestCommitVersionOutsideOfRetentionWindow":10}
E) next run: fell_back=False  parquet 8 -> 2
PASS: loop reproduced with flag off, broken with flag on.
```

Stage C is the loop reproduced against real Delta 3.3.1: two consecutive runs both fall back and
the watermark never becomes usable. Stage E is the proof it is broken: `fell_back=False` means
the LITE statement succeeded, and the parquet count dropping 8 -> 2 means it actually deleted
files. Row count verified unchanged at 10 throughout.
