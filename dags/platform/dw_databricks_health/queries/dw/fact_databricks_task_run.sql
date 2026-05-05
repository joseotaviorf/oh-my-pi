-- ============================================================================
-- fact_databricks_task_run.sql
--
-- Per Airflow-task-run health fact joining Databricks system tables, the
-- cluster-utilisation snapshot from datalake_databricks_health.daily_cluster
-- _health (PR 23079), and per-stage Spark execution metrics from
-- datalake_databricks_health.spark_stage_metrics (PR 23080).
--
-- Grain: one row per
--   (id_databricks_workspace, id_databricks_run, id_databricks_task_run)
-- For the bietlejuice framework that is one row per Airflow task instance,
-- because query_delta DAGs spin up a job cluster per task.
--
-- Source tables:
--   - system.lakeflow.job_task_run_timeline           (spine — per-task-run)
--   - system.lakeflow.job_run_timeline                (parent run state)
--   - system.compute.clusters                         (cluster spec — latest)
--   - system.billing.usage                            (DBU per cluster-window)
--   - system.billing.list_prices                      (AWS USD list rate per DBU SKU)
--   - datalake_databricks_health.daily_cluster_health (PR 23079 — P50/P95 util)
--   - datalake_databricks_health.spark_stage_metrics  (PR 23080 — per stage)
--
-- Filters:
--   - tags['provisioner'] = 'bietlejuice'   (framework-managed clusters only)
--   - tags['environment'] = '{environment}' (scope to local workspace)
--
-- Cost attribution caveat: billing rows whose usage_start_time falls within
-- the task window are summed without time-slice apportionment. For job
-- clusters (1 task = 1 cluster) this is a 1:1 attribution. For shared
-- interactive clusters this over-attributes — the same billing rows are
-- counted by every concurrent task. Documented in metadata.
--
-- USD conversion uses system.billing.list_prices.pricing.default (list rate
-- in USD per DBU, AWS cloud) joined on sku_name + valid time window. No
-- Graviton or instance-pool discount applies to DBUs (validated in
-- bietlejuice/spark_debugging/mcp_a4_dbu_list_prices.sql) — savings on
-- those come from EC2 cost and faster wall-clock, not the DBU rate.
-- Promotional / committed-use discounts are NOT applied; use
-- pricing.effective_list.default in a follow-up if enterprise negotiated
-- pricing is needed.
--
-- Stage-attribution strategy:
--   spark_stage_metrics is keyed by (id_spark_app, id_stage, id_stage_attempt)
--   plus dag_id (parsed from the event-log path). The path layout lacks
--   task_id and cluster_id, so we attribute each Spark application to a task
--   by matching dag_id + spark_app_first_seen ∈ [ts_task_started, ts_task_
--   ended]. For DAGs with sequential tasks (the vast majority of query_delta
--   DAGs) this is unique. For DAGs with PARALLEL tasks of the same dag_id,
--   the same spark_app may match multiple task windows and the
--   `is_stage_attribution_ambiguous` flag fires (spark_app_count > 1).
-- ============================================================================
WITH latest_cluster_spec AS (
    SELECT
        cluster_id,
        workspace_id,
        cluster_name,
        cluster_source,
        driver_node_type,
        worker_node_type,
        dbr_version,
        worker_count,
        min_autoscale_workers,
        max_autoscale_workers,
        driver_instance_pool_id,
        worker_instance_pool_id,
        tags
    FROM (
        SELECT
            c.*,
            ROW_NUMBER() OVER (
                PARTITION BY c.cluster_id, c.workspace_id
                ORDER BY c.change_time DESC
            ) AS rn
        FROM
            system.compute.clusters c
        WHERE
            DATE(c.change_time) <= DATE('{load_end_date}')
            AND c.tags['provisioner'] = 'bietlejuice'
            AND c.tags['environment'] = '{environment}'
    )
    WHERE
        rn = 1
),
task_run_spine AS (
    -- Aggregate event-timeline rows down to one per run_id (task run).
    -- job_task_run_timeline emits a new row every time a task transitions
    -- compute or status; we collapse the lifecycle here.
    -- Column mapping: run_id → task_run_id, job_run_id → run_id.
    SELECT
        workspace_id,
        job_id,
        job_run_id                                         AS run_id,
        run_id                                             AS task_run_id,
        FIRST(task_key)                                    AS task_key,
        FIRST(compute_ids[0])                              AS cluster_id,
        MIN(period_start_time)                             AS ts_task_started,
        MAX(period_end_time)                               AS ts_task_ended,
        MAX(setup_duration_seconds)                        AS setup_duration_seconds,
        MAX_BY(result_state, period_start_time)            AS task_result_state,
        DATE(MIN(period_start_time))                       AS dt_task_started
    FROM
        system.lakeflow.job_task_run_timeline
    WHERE
        DATE(period_start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND compute_ids IS NOT NULL
        AND ARRAY_SIZE(compute_ids) > 0
    GROUP BY
        workspace_id, job_id, job_run_id, run_id
),
parent_run AS (
    -- Same aggregation pattern for the parent run.
    SELECT
        workspace_id,
        run_id,
        FIRST(run_type)                                    AS run_type,
        MAX_BY(result_state, period_start_time)            AS run_result_state,
        MIN(period_start_time)                             AS ts_run_started,
        MAX(period_end_time)                               AS ts_run_ended
    FROM
        system.lakeflow.job_run_timeline
    WHERE
        DATE(period_start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        workspace_id, run_id
),
prices_per_sku AS (
    -- One row per (sku, validity window). Filter to AWS DBU prices in USD.
    -- price_end_time is NULL for the currently-effective price. We rely on
    -- list price (pricing.default); promotional / effective_list pricing
    -- can be swapped in here if QuintoAndar negotiates enterprise rates.
    SELECT
        sku_name,
        pricing.default                                    AS unit_price_usd,
        price_start_time,
        price_end_time
    FROM
        system.billing.list_prices
    WHERE
        cloud             = 'AWS'
        AND usage_unit    = 'DBU'
        AND currency_code = 'USD'
        AND price_start_time <= TIMESTAMP('{load_end_date}')
        AND (price_end_time IS NULL OR price_end_time >= TIMESTAMP('{load_start_date}'))
),
billing_per_task AS (
    SELECT
        s.workspace_id,
        s.run_id,
        s.task_run_id,
        SUM(u.usage_quantity)                              AS dbu_consumed,
        SUM(u.usage_quantity * COALESCE(p.unit_price_usd, 0))
                                                           AS cost_usd_estimate,
        FIRST(u.sku_name)                                  AS pricing_sku,
        FIRST(p.unit_price_usd)                            AS dbu_rate_usd
    FROM
        task_run_spine s
    LEFT JOIN
        system.billing.usage u
            ON  u.workspace_id              = s.workspace_id
            AND u.usage_metadata.cluster_id = s.cluster_id
            AND u.usage_unit                = 'DBU'
            AND u.usage_start_time         >= s.ts_task_started
            AND u.usage_start_time          < s.ts_task_ended
            AND DATE(u.usage_start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    LEFT JOIN
        prices_per_sku p
            ON  p.sku_name           = u.sku_name
            AND u.usage_start_time  >= p.price_start_time
            AND (p.price_end_time IS NULL OR u.usage_start_time < p.price_end_time)
    GROUP BY
        s.workspace_id, s.run_id, s.task_run_id
),
stage_per_app AS (
    -- Roll up spark_stage_metrics from per-stage to per-spark-application,
    -- and record the application's first-seen timestamp for the time-window
    -- join in `stage_per_task` below.
    SELECT
        dag_id,
        id_spark_app,
        MIN(ts_stage_submitted)                            AS spark_app_first_seen,
        MAX(ts_stage_completed)                            AS spark_app_last_seen,
        COUNT(*)                                           AS stage_count,
        SUM(CASE WHEN is_stage_failed THEN 1 ELSE 0 END)   AS failed_stage_count,
        SUM(executor_run_time_ms)                          AS total_executor_run_time_ms,
        -- Convert ns → ms so the unit lines up with the other duration cols.
        SUM(executor_cpu_time_ns) / 1000000                AS total_executor_cpu_time_ms,
        SUM(disk_bytes_spilled)                            AS total_disk_bytes_spilled,
        SUM(memory_bytes_spilled)                          AS total_memory_bytes_spilled,
        MAX(peak_execution_memory_bytes)                   AS max_peak_execution_memory_bytes,
        SUM(input_bytes_read)                              AS total_input_bytes_read,
        SUM(output_bytes_written)                          AS total_output_bytes_written,
        SUM(shuffle_read_local_bytes + shuffle_read_remote_bytes)
                                                           AS total_shuffle_bytes_read,
        SUM(shuffle_write_bytes)                           AS total_shuffle_bytes_written,
        -- Extended parser columns (require spark.eventLog.logStageExecutorMetrics=true,
        -- enabled by PR 23078). NULL for stages parsed before that config landed.
        MAX(max_jvm_heap_bytes)                            AS max_jvm_heap_bytes,
        SUM(total_gc_time_ms)                              AS total_gc_time_ms,
        MAX(max_task_run_time_ms)                          AS max_task_run_time_ms,
        MAX(task_skew_ratio)                               AS max_task_skew_ratio,
        -- Failure reason of the last failed stage in this spark_app
        -- (chronologically). NULL when no stage in the app failed.
        MAX_BY(
            CASE WHEN is_stage_failed THEN stage_failure_reason END,
            ts_stage_completed
        )                                                  AS last_stage_failure_reason
    FROM
        datalake_databricks_health.spark_stage_metrics
    WHERE
        dt_stage_completed BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        dag_id, id_spark_app
),
stage_per_task AS (
    -- Attribute each spark_app to the matching task by dag_id + start time
    -- falling within the task window. Sequential-task DAGs match uniquely;
    -- DAGs with concurrent tasks of the same dag_id may match the same
    -- spark_app to multiple tasks (`spark_app_count > 1` ⇒ ambiguous).
    SELECT
        s.workspace_id,
        s.run_id,
        s.task_run_id,
        COUNT(DISTINCT spa.id_spark_app)                   AS spark_app_count,
        SUM(spa.stage_count)                               AS stage_count,
        SUM(spa.failed_stage_count)                        AS failed_stage_count,
        SUM(spa.total_executor_run_time_ms)                AS total_executor_run_time_ms,
        SUM(spa.total_executor_cpu_time_ms)                AS total_executor_cpu_time_ms,
        SUM(spa.total_disk_bytes_spilled)                  AS total_disk_bytes_spilled,
        SUM(spa.total_memory_bytes_spilled)                AS total_memory_bytes_spilled,
        MAX(spa.max_peak_execution_memory_bytes)           AS max_peak_execution_memory_bytes,
        SUM(spa.total_input_bytes_read)                    AS total_input_bytes_read,
        SUM(spa.total_output_bytes_written)                AS total_output_bytes_written,
        SUM(spa.total_shuffle_bytes_read)                  AS total_shuffle_bytes_read,
        SUM(spa.total_shuffle_bytes_written)               AS total_shuffle_bytes_written,
        MAX(spa.max_jvm_heap_bytes)                        AS max_jvm_heap_bytes,
        SUM(spa.total_gc_time_ms)                          AS total_gc_time_ms,
        MAX(spa.max_task_run_time_ms)                      AS max_task_run_time_ms,
        MAX(spa.max_task_skew_ratio)                       AS max_task_skew_ratio,
        -- Carry forward the most recent failure reason across all matched apps
        -- so consumers don't have to drill into spark_stage_metrics for the
        -- typical "what crashed?" question.
        MAX_BY(spa.last_stage_failure_reason, spa.spark_app_last_seen)
                                                           AS last_stage_failure_reason
    FROM
        task_run_spine s
    INNER JOIN
        latest_cluster_spec lcs
            ON  lcs.cluster_id   = s.cluster_id
            AND lcs.workspace_id = s.workspace_id
    INNER JOIN
        stage_per_app spa
            ON  spa.dag_id               = lcs.tags['application']
            AND spa.spark_app_first_seen >= s.ts_task_started
            AND spa.spark_app_first_seen <  s.ts_task_ended
    GROUP BY
        s.workspace_id, s.run_id, s.task_run_id
),
stage_per_task_clean AS (
    -- When attribution is ambiguous (a single spark_app matched multiple
    -- concurrent tasks of the same dag_id), the rolled-up SUMs and MAXs are
    -- over-counted and would silently corrupt downstream aggregates. NULL the
    -- metric columns in that case so SUM/AVG skip them; consumers explicitly
    -- opting in can `WHERE NOT is_stage_attribution_ambiguous`. The diagnostic
    -- columns (`spark_app_count`, `last_stage_failure_reason`) and the
    -- `failed_stage_count` boolean signal stay populated either way — they're
    -- still useful even when the value is over-counted.
    SELECT
        workspace_id,
        run_id,
        task_run_id,
        spark_app_count,
        spark_app_count > 1                                                                  AS is_stage_attribution_ambiguous,
        last_stage_failure_reason,
        IF(spark_app_count > 1, NULL, stage_count)                                           AS stage_count,
        IF(spark_app_count > 1, NULL, failed_stage_count)                                    AS failed_stage_count,
        IF(spark_app_count > 1, NULL, total_executor_run_time_ms)                            AS total_executor_run_time_ms,
        IF(spark_app_count > 1, NULL, total_executor_cpu_time_ms)                            AS total_executor_cpu_time_ms,
        IF(spark_app_count > 1, NULL, total_disk_bytes_spilled)                              AS total_disk_bytes_spilled,
        IF(spark_app_count > 1, NULL, total_memory_bytes_spilled)                            AS total_memory_bytes_spilled,
        IF(spark_app_count > 1, NULL, max_peak_execution_memory_bytes)                       AS max_peak_execution_memory_bytes,
        IF(spark_app_count > 1, NULL, total_input_bytes_read)                                AS total_input_bytes_read,
        IF(spark_app_count > 1, NULL, total_output_bytes_written)                            AS total_output_bytes_written,
        IF(spark_app_count > 1, NULL, total_shuffle_bytes_read)                              AS total_shuffle_bytes_read,
        IF(spark_app_count > 1, NULL, total_shuffle_bytes_written)                           AS total_shuffle_bytes_written,
        IF(spark_app_count > 1, NULL, max_jvm_heap_bytes)                                    AS max_jvm_heap_bytes,
        IF(spark_app_count > 1, NULL, total_gc_time_ms)                                      AS total_gc_time_ms,
        IF(spark_app_count > 1, NULL, max_task_run_time_ms)                                  AS max_task_run_time_ms,
        IF(spark_app_count > 1, NULL, max_task_skew_ratio)                                   AS max_task_skew_ratio
    FROM
        stage_per_task
)
SELECT
    XXHASH64(s.workspace_id, s.run_id, s.task_run_id)              AS sk_databricks_task_run,
    XXHASH64(s.workspace_id, s.run_id)                             AS sk_databricks_run,
    XXHASH64(s.workspace_id, s.cluster_id)                         AS sk_databricks_cluster,
    CAST(DATE_FORMAT(s.dt_task_started, 'yyyyMMdd') AS INT)        AS sk_task_started_date,

    s.workspace_id                                                 AS id_databricks_workspace,
    s.run_id                                                       AS id_databricks_run,
    s.task_run_id                                                  AS id_databricks_task_run,
    s.job_id                                                       AS id_databricks_job,
    s.task_key                                                     AS id_databricks_task_key,
    s.cluster_id                                                   AS id_cluster,
    -- Click-through URL to the Databricks UI for this run. Per-workspace mapping
    -- mirrors `dags/platform/enrich_databricks/spark_jobs/prod_conf.yml` and `forno_conf.yml`.
    -- New workspaces should be added to that yaml AND here in the same PR.
    CONCAT(
        CASE s.workspace_id
            WHEN 4531937035440038 THEN 'https://dbc-931ee6e0-6803.cloud.databricks.com'  -- QuintoAndar
            WHEN 6170817193817    THEN 'https://dbc-939a4590-9353.cloud.databricks.com'  -- Prod
            WHEN 4033397625841925 THEN 'https://dbc-324f044d-4b9d.cloud.databricks.com'  -- Forno
            ELSE CONCAT('https://accounts.cloud.databricks.com/workspaces/', CAST(s.workspace_id AS STRING))
        END,
        '/jobs/', CAST(s.job_id AS STRING),
        '/runs/', CAST(s.run_id AS STRING)
    )                                                              AS databricks_run_url,

    lcs.tags['application']                                        AS dag_name,
    lcs.tags['application']                                        AS airflow_dag_id,
    s.task_key                                                     AS airflow_task_id,
    -- Governance / attribution tags. Set by the bietlejuice cluster builder; surfaced
    -- here as first-class columns so cost dashboards can group by team / cost center
    -- without re-parsing custom_tags. See `bietlejuice/prod_conf.yml` and `forno_conf.yml`
    -- (cluster_anchor_base.custom_tags) for the canonical source.
    lcs.tags['owner']                                              AS team_owner,
    lcs.tags['cost-center']                                        AS cost_center,
    lcs.tags['ecosystem']                                          AS ecosystem,
    lcs.tags['environment']                                        AS environment,
    lcs.tags['data-classification']                                AS data_classification,
    lcs.tags['provisioner']                                        AS provisioner,
    lcs.cluster_name,
    lcs.cluster_source,
    lcs.driver_node_type,
    lcs.worker_node_type,
    lcs.dbr_version,
    lcs.worker_count,
    lcs.min_autoscale_workers,
    lcs.max_autoscale_workers,
    dch.peak_concurrent_workers,
    pr.run_type,
    pr.run_result_state,
    s.task_result_state,

    s.setup_duration_seconds,
    -- Cluster-startup-phase timing from daily_cluster_health (Overwatch source).
    -- These are cluster-day attributes — every task run on the same (cluster, date)
    -- carries identical values. SUM aggregations at the task-run grain over-count;
    -- dedupe to (id_cluster, dt_task_started) before summing.
    dch.pre_init_script_seconds,
    dch.init_script_seconds,
    dch.post_init_script_seconds,
    dch.cluster_startup_seconds,
    BIGINT(unix_timestamp(s.ts_task_ended) - unix_timestamp(s.ts_task_started))
                                                                   AS total_duration_seconds,
    BIGINT(unix_timestamp(s.ts_task_ended) - unix_timestamp(s.ts_task_started))
        - COALESCE(s.setup_duration_seconds, 0)                    AS execution_duration_seconds,
    ROUND(COALESCE(b.dbu_consumed, 0), 4)                          AS dbu_consumed,
    -- Primary USD cost trail derived from system.billing.usage × system.billing.list_prices.
    ROUND(COALESCE(b.cost_usd_estimate, 0), 4)                     AS cost_usd_estimate,
    b.dbu_rate_usd,
    b.pricing_sku,
    -- Overwatch-derived cluster-day cost cross-check (USD). Same cluster-day dedupe
    -- caveat as the *_script_seconds columns above — these are cluster-day, not task-run.
    dch.total_dbu_cost_overwatch_usd,
    dch.total_ec2_cost_overwatch_usd,
    dch.p50_driver_cpu_busy_percent,
    dch.p95_driver_cpu_busy_percent,
    dch.p50_driver_cpu_wait_percent,
    dch.p95_driver_cpu_wait_percent,
    dch.p50_driver_mem_used_percent,
    dch.p95_driver_mem_used_percent,
    dch.p50_worker_cpu_busy_percent,
    dch.p95_worker_cpu_busy_percent,
    dch.p50_worker_cpu_wait_percent,
    dch.p95_worker_cpu_wait_percent,
    dch.p50_worker_mem_used_percent,
    dch.p95_worker_mem_used_percent,
    dch.nvme_utilization_pct_p95,

    -- Per-task-run Spark execution metrics (rolled up from spark_stage_metrics).
    -- See `stage_per_task` and `stage_per_task_clean` CTEs above for the
    -- time-window attribution rules and the ambiguity-NULL contract.
    sptc.stage_count,
    sptc.failed_stage_count,
    sptc.spark_app_count,
    sptc.total_executor_run_time_ms,
    sptc.total_executor_cpu_time_ms,
    sptc.total_disk_bytes_spilled,
    sptc.total_memory_bytes_spilled,
    sptc.max_peak_execution_memory_bytes,
    sptc.total_input_bytes_read,
    sptc.total_output_bytes_written,
    sptc.total_shuffle_bytes_read,
    sptc.total_shuffle_bytes_written,
    sptc.max_jvm_heap_bytes,
    sptc.total_gc_time_ms,
    sptc.max_task_run_time_ms,
    sptc.max_task_skew_ratio,
    sptc.last_stage_failure_reason,

    s.task_result_state = 'SUCCEEDED'                              AS is_success,
    s.task_result_state = 'FAILED'                                 AS is_failed,
    dch.is_photon,
    dch.is_pool_backed,
    s.setup_duration_seconds > 90                                  AS is_pool_acquisition_slow,
    lcs.tags['sensitive-data'] = 'true'                            AS is_sensitive_data,
    sptc.workspace_id IS NOT NULL                                  AS has_stage_data,
    COALESCE(sptc.is_stage_attribution_ambiguous, FALSE)           AS is_stage_attribution_ambiguous,

    s.dt_task_started,

    s.ts_task_started,
    s.ts_task_ended,
    pr.ts_run_started,
    pr.ts_run_ended,
    CURRENT_TIMESTAMP()                                            AS ts_load,

    YEAR(s.dt_task_started)                                        AS year,
    MONTH(s.dt_task_started)                                       AS month,
    DAY(s.dt_task_started)                                         AS day

FROM
    task_run_spine     s
JOIN
    latest_cluster_spec lcs
        ON  lcs.cluster_id   = s.cluster_id
        AND lcs.workspace_id = s.workspace_id
LEFT JOIN
    parent_run pr
        ON  pr.workspace_id = s.workspace_id
        AND pr.run_id       = s.run_id
LEFT JOIN
    billing_per_task b
        ON  b.workspace_id = s.workspace_id
        AND b.run_id       = s.run_id
        AND b.task_run_id  = s.task_run_id
LEFT JOIN
    datalake_databricks_health.daily_cluster_health dch
        ON  dch.id_cluster     = s.cluster_id
        AND dch.dt_cluster_run = s.dt_task_started
LEFT JOIN
    stage_per_task_clean sptc
        ON  sptc.workspace_id = s.workspace_id
        AND sptc.run_id       = s.run_id
        AND sptc.task_run_id  = s.task_run_id
