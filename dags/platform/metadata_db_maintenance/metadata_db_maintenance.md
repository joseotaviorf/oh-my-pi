# airflow.metadata_db_maintenance

## Short

Reports Airflow metadata-database table sizes and deletes rows older than the retention window.

## Long

`report_table_sizes` logs the 25 largest tables visible on the connection's `search_path`, with `reltuples` as an approximate row count. `clean_metadata_db` deletes rows older than `retention_days` (default 90), or older than `clean_before_timestamp` when that param is set.

The large tables are purged in small chunks, each in its own transaction with `statement_timeout = 60s` and `lock_timeout = 5s`, and without archive copies. `dag_run`, `log` and `job` take turns, one chunk each per round, with `pause_seconds` between rounds. New chunks stop after `max_runtime_minutes` (default 45), and the next daily run continues where this one stopped; no progress cursor is stored.

- `dag_run`: old runs are chosen by `start_date`, oldest first, keeping the latest scheduled run per DAG (the same keep_last rule as `airflow.utils.db_cleanup`). Their task instances are deleted run by run through the `ti_dag_run (dag_id, run_id)` index, because `task_instance.start_date` has no index. `xcom`, `task_instance_history`, `task_fail`, `task_reschedule`, `rendered_task_instance_fields`, `task_map` and the note tables go with them through `ON DELETE CASCADE`.
- `log`: chunks by `dttm` through `idx_log_dttm`.
- `job`: chunks by `latest_heartbeat` through `job_type_heart`.

Chunk sizes start at `dag_runs_per_chunk` and `rows_per_chunk`, double after a chunk under 2 s and halve after one over 15 s. A chunk that hits a statement or lock timeout is rolled back and retried at half size; failing at size 1 fails the task. Before deleting, the task logs the `EXPLAIN` plans and skips `task_instance` or `log` if their delete would scan the whole table, failing the task at the end.

`task_reschedule`, `dataset_event`, `sla_miss`, `callback_request` and the celery tables are small and still go through `airflow.utils.db_cleanup.run_cleanup`. `run_cleanup` logs and swallows database errors, so the task afterwards checks that none of these tables still has rows older than the cutoff, and fails if one does. `run_cleanup` always copies the rows into `_airflow_deleted__<table>__<timestamp>` before deleting, even with `skip_archive=True`, and a killed task strands that copy. `drop_archive_tables` runs with `trigger_rule="all_done"` and sweeps any `_airflow_deleted__*` table left for the tables in scope.

`dry_run` logs the plans, the `run_cleanup` counts and the number of old `dag_run`, `log` and `job` rows, plus the `task_instance` row estimate, and deletes nothing.

`dag_run`, `task_instance`, `task_instance_history`, `task_fail`, `log`, and `dataset_event` are replicated hourly into `hive.datalake_astro_clean`, so analytics history survives the delete.

Dataset-triggered DAGs decide what to run from `dataset_event` rows newer than their last successful dataset-triggered run, so purging `dataset_event` older than the retention window can drop pending triggers for a DAG that has not run in that window. At 90 days that DAG is already stale.

Deleting rows does not shrink the database files; Postgres reuses the freed space. Reclaiming disk needs `pg_repack` or `VACUUM FULL`.

Excluded on purpose: `dag` (deletes DAG records), `trigger` (rows belong to live deferred tasks), `session` and `import_error` (live state, negligible size).
