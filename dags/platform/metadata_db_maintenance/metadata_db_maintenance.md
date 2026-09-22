# airflow.metadata_db_maintenance

## Short

Reports Airflow metadata-database table sizes and deletes rows older than the retention window.

## Long

`report_table_sizes` logs the 25 largest `public` tables (`pg_total_relation_size`). `clean_metadata_db` deletes rows older than `retention_days` (default 90), or older than `clean_before_timestamp` when that param is set, through `airflow.utils.db_cleanup.run_cleanup`.

`skip_archive=True` does not skip the archive copy. `airflow.utils.db_cleanup._do_delete` always creates `_airflow_deleted__<table>__<timestamp>` with `CREATE TABLE AS SELECT`, deletes the source rows through it, and then drops it because the flag is set. A task killed between the delete and the drop strands that copy, so `drop_archive_tables` runs with `trigger_rule="all_done"` and sweeps any `_airflow_deleted__*` left for the tables in scope. `dag_run`, `task_instance`, `task_instance_history`, `task_fail`, `log`, and `dataset_event` are replicated hourly into `hive.datalake_astro_clean`, so analytics history survives the delete.

Deletes run in `batch_size_days` chunks (default 7), oldest first, at most `max_batches_per_run` (default 10) per run, so a single run never copies more than a bounded slice. The ladder starts from the oldest `log` row and always ends at the resolved cutoff. A capped run stops early and the next run resumes, because purging advances the oldest `log` row; no progress cursor is stored. Steady state after the backlog drains is one batch per week.

Dataset-triggered DAGs decide what to run from `dataset_event` rows newer than their last successful dataset-triggered run, so purging `dataset_event` older than the retention window can drop pending triggers for a DAG that has not run in that window. At 90 days that DAG is already stale.

Excluded on purpose: `dag` (deletes DAG records), `trigger` (rows belong to live deferred tasks), `session` and `import_error` (live state, negligible size).
