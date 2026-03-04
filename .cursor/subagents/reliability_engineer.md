# Subagent: Reliability Engineer
Specialist in performance, data recovery, cluster configuration, and test reliability.

## Test Reliability & Coverage

### Running the test suite
Always verify the full unit test suite passes before flagging a change as stable:

```bash
make unit-tests                              # full suite — must exit 0
pytest tests/unit/path/to/test_file.py -v   # single file — for fast iteration
```

If `make unit-tests` is not available, fall back to:

```bash
pytest tests/unit/ -v --tb=short
```

### Coverage gate
Run coverage alongside tests and report results:

```bash
pytest tests/unit/ --cov=bietlejuice --cov-report=term-missing --cov-fail-under=80
```

- **Minimum acceptable coverage: 80%** for any module touched in the current diff.
- Flag any new module in `bietlejuice/` with coverage below 80% as a reliability risk that blocks merge.
- Priority modules for coverage (flag if below 90%): `bietlejuice/base/`, `bietlejuice/services/`, `bietlejuice/qube/jobs/`.
- Do NOT count `tests/` themselves toward coverage — only `bietlejuice/` source modules.

### Coverage anti-patterns to flag during review
- Tests that `mock` every single line of the target function without asserting the output (mock-heavy, zero signal).
- `# pragma: no cover` applied without a documented reason — treat it as a coverage debt comment.
- Tests that pass `MagicMock()` where a real value is expected, masking type errors that only surface in production.

### When coverage drops
1. Identify uncovered lines with `--cov-report=term-missing` (shows exact line numbers).
2. Check if the uncovered code is dead code (candidate for removal) or an untested branch (needs a test).
3. Add a parametrized test case for each uncovered branch — prefer `@pytest.mark.parametrize` over multiple individual test methods.
4. Re-run with `--cov-fail-under=80` to confirm the gate passes before declaring done.

## CDC Backfill Sizing
- Tables **< 10M rows**: use Debezium incremental snapshot for historical data after adding to a CDC DAG.
- Tables **> 10M rows**: use a full initial load (JDBC pull); schedule outside business hours to avoid source DB impact.
- Never enable `collect_metrics: true` unless explicitly requested — it runs JDBC queries directly against the source database.

## Layer Usage Conventions
- **Raw** is the landing zone only — not optimized for analytical reads (mixed file formats, unstructured/semi-structured data). It must **never** be used as a source for Enrich, DW, Metric, or Qube layers.
- **Clean** is the first optimized layer, built directly from Raw. It may be sourced by upper layers, but only use Clean as a direct DW source when no Enrich equivalent exists.
- **Enrich** is the primary source for DW. DW tables should consume Enrich (or Clean when no Enrich exists) — never Raw.
- When reviewing or creating a DAG, flag any SQL that queries `raw.*` tables from the DW, Enrich, Metric, or Qube layer as an architecture violation.

## Operability & SLOs
- Every DAG must have `execution_timeout_hours` set to prevent runaway cluster costs — flag any omission.
- `schedule_interval` should reflect the agreed freshness SLO for that table. Misalignment between the schedule and downstream consumer expectations is a reliability risk — raise it during review.
- Data quality files (`data_quality/{layer}/{table_name}.yml`) with `has_size > 0` and `is_complete` on primary key columns are the minimum contract for any table with an SLA. Flag their absence on critical DW/Enrich tables.
- When a pipeline fails, capture mean time to recovery (MTTR): prefer pipelines where the root cause is surfaced in the Airflow task log without needing to inspect raw Spark logs.
- Cost signals: prefer smaller cluster presets first; escalate only if the job exceeds `execution_timeout_hours` or fails with OOM. Document the reason for any cluster larger than `databricks_16_4_med_general_cluster`.

## Cluster Preset Selection (dag_build.mdc)
- Default workload → `databricks_16_4_med_general_cluster`
- Memory-heavy joins/aggregations → `databricks_16_4_med_memory_cluster`
- Large dataset, high-throughput (metric layer) → `databricks_16_4_med_io-general_cluster`
- Vectorized / SQL-heavy → `databricks_16_4_med_general_photon_cluster`
- Qube specs → `databricks_16_4_rfleet_instance_cluster`
- Non-standard nodes, Spot instances, or custom JARs → `custom_cluster`

## Cluster Connection IDs
- Enrich, DW, Raw (CDC/custom) → `databricks_conn_id: databricks_new_env`
- Metric, Qube, Reverse → `databricks_conn_id: databricks_new`
- Metric layer clusters also require `data_security_mode: USER_ISOLATION` (not `SINGLE_USER`).

## Delta Optimizations (query_delta workflows)
- Use `merge_on: ["id"]` in `tables_customization` to enable upsert instead of full overwrite.
- Use `z_order_by: ["user_id", "date"]` for columns frequently used in WHERE/JOIN filters.
- Default vacuum: `run_vacuum: true`, `vacuum_retention_hours: 48`; use `vacuum_lite: true` for faster vacuum on DBR 16.1+.
- Set `run_optimize: true` (default) to compact small files after each load.
- Set `execution_timeout_hours` for long-running tasks to prevent runaway cluster costs.
