-- ============================================================================
-- query_history.sql
--
-- Daily snapshot of every SQL statement executed against Databricks compute,
-- sourced from system.query.history. One row per statement_id.
--
-- Source table: system.query.history (Databricks system table; refreshes
-- every few minutes, retains ~90 days). Schema reference:
-- https://docs.databricks.com/aws/en/admin/system-tables/query-history
--
-- Filters:
--   - start_time falls within the rolling load window (recovers any
--     statements that landed late in the system table).
--
-- query_parameters is intentionally NOT exposed: its struct schema is
-- pathological (contains every literal value in the query, deeply recursive
-- via expression IDs), is CMK-redacted in many environments, and would
-- bloat downstream serdes. Consumers that need it should query
-- system.query.history directly.
--
-- query_tags is preserved as a map (allowed in raw / clean / enrich layers
-- per naming conventions; would be flattened if promoted to DW).
--
-- Bietlejuice cluster filter: NOT applied here. This table is the single
-- source of truth for *all* Databricks query activity (warehouses, ad-hoc
-- analysts, jobs); consumers can filter on `compute_type` / `id_cluster`
-- / `id_warehouse` downstream when they need to scope to specific compute.
-- ============================================================================
SELECT
    qh.statement_id                                                AS id_statement,
    qh.session_id                                                  AS id_session,
    qh.account_id                                                  AS id_databricks_account,
    qh.workspace_id                                                AS id_databricks_workspace,
    qh.executed_by_user_id                                         AS id_user,
    qh.executed_as_user_id                                         AS id_executed_as_user,

    qh.compute.type                                                AS compute_type,
    qh.compute.cluster_id                                          AS id_cluster,
    qh.compute.warehouse_id                                        AS id_warehouse,

    qh.query_source.job_info.job_id                                AS id_databricks_job,
    qh.query_source.job_info.job_run_id                            AS id_databricks_run,
    qh.query_source.job_info.job_task_run_id                       AS id_databricks_task_run,
    qh.query_source.dashboard_id                                   AS id_dashboard,
    qh.query_source.legacy_dashboard_id                            AS id_legacy_dashboard,
    qh.query_source.alert_id                                       AS id_alert,
    qh.query_source.notebook_id                                    AS id_notebook,
    qh.query_source.sql_query_id                                   AS id_sql_query,
    qh.query_source.genie_space_id                                 AS id_genie_space,
    qh.query_source.pipeline_info.pipeline_id                      AS id_pipeline,
    qh.query_source.pipeline_info.update_id                        AS id_pipeline_update,
    qh.cache_origin_statement_id                                   AS id_cache_origin_statement,

    qh.executed_by                                                 AS executed_by_email,
    qh.executed_as                                                 AS executed_as_user_name,

    qh.statement_type,
    qh.execution_status,
    qh.client_application,
    qh.client_driver,
    qh.statement_text,
    qh.error_message,

    qh.total_duration_ms,
    qh.waiting_for_compute_duration_ms,
    qh.waiting_at_capacity_duration_ms,
    qh.execution_duration_ms,
    qh.compilation_duration_ms,
    qh.total_task_duration_ms,
    qh.result_fetch_duration_ms,

    qh.read_partitions,
    qh.pruned_files,
    qh.read_files,
    qh.read_rows,
    qh.produced_rows,
    qh.read_bytes,
    qh.read_io_cache_percent,
    qh.spilled_local_bytes,
    qh.written_bytes,
    qh.written_rows,
    qh.written_files,
    qh.shuffle_read_bytes,
    qh.pruned_files_bytes,
    qh.read_files_bytes,

    qh.from_result_cache                                           AS is_from_result_cache,

    qh.query_tags                                                  AS query_tags_json,

    DATE(qh.start_time)                                            AS dt_started,
    qh.start_time                                                  AS ts_started,
    qh.end_time                                                    AS ts_ended,
    qh.update_time                                                 AS ts_updated,
    CURRENT_TIMESTAMP()                                            AS ts_load,

    YEAR(qh.start_time)                                            AS year,
    MONTH(qh.start_time)                                           AS month,
    DAY(qh.start_time)                                             AS day

FROM
    system.query.history qh
WHERE
    qh.start_time >= TIMESTAMP('{load_start_date}')
    AND qh.start_time <  TIMESTAMP('{load_end_date}')
