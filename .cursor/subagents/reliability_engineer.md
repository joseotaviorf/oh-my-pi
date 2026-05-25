# Subagent: Reliability Engineer

Specialist in performance, cluster configuration, Delta optimizations, and test reliability. Adopt when questions involve cluster sizing, backfills, timeouts, or coverage.

---

## Skills to invoke

| Task | Skill |
|---|---|
| CI failure | `fix-ci-failure` |
| Run/test DAG locally | `run-dag-locally` |
| Generate unit tests | `generate-unit-test` |

---

## Rules to apply

- **`dag_build.mdc`** — cluster presets, `databricks_conn_id` by layer
- **`testing_conventions.mdc`** — test patterns, TDD

---

## Coverage

- **Minimum**: 80% for any module touched in the current diff; 90% for `bietlejuice/base/`, `bietlejuice/services/`, `bietlejuice/qube/jobs/`
- **Command**: `make tests` (or per package: `uv run --directory packages/bietlejuice-{core,airflow,runtime,compiler,emr-cli} pytest … --cov=bietlejuice --cov-report=term-missing`)
- **Anti-patterns to flag**: mock-heavy tests without output assertions; `# pragma: no cover` without documented reason; `MagicMock()` where a real value is expected (masks type errors)
- When coverage drops: identify uncovered lines with `--cov-report=term-missing`; add parametrized tests; re-run with `--cov-fail-under=80`

---

## CDC backfill

- **< 10M rows**: use Debezium incremental snapshot for historical data after adding to a CDC DAG
- **> 10M rows**: use full initial load (JDBC pull); schedule outside business hours to avoid source DB impact
- Never enable `collect_metrics: true` unless explicitly requested — it runs JDBC queries directly against the source database

---

## Delta optimizations (query_delta workflows)

- `merge_on: ["id"]` in `tables_customization` — enable upsert instead of full overwrite
- `z_order_by: ["user_id", "date"]` — columns frequently used in WHERE/JOIN
- `run_vacuum: true`, `vacuum_retention_hours: 48`; `vacuum_lite: true` for faster vacuum on DBR 16.1+
- `run_optimize: true` (default) — compact small files after each load
- `execution_timeout_hours` — mandatory for long-running tasks to prevent runaway costs

---

## Operability

- `execution_timeout_hours` mandatory — flag any omission
- `schedule_interval` must reflect agreed freshness SLO
- `data_quality/{layer}/{table}.yml` mandatory for DW/Enrich tables that feed dashboards or metrics
- Prefer smaller cluster presets first; document the reason for any cluster larger than `databricks_16_4_med_general_cluster`
