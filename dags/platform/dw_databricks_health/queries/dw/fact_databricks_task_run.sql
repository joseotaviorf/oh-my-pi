-- ============================================================================
-- fact_databricks_task_run.sql
--
-- Per task-run health fact joining Databricks system tables, the
-- cluster-utilisation snapshot from datalake_databricks_health.daily_cluster
-- _health (PR 23079), and per-stage Spark execution metrics from
-- datalake_databricks_health.spark_stage_metrics (PR 23080).
--
-- Grain: one row per
--   (id_databricks_workspace, id_databricks_run, id_databricks_task_run)
-- A Databricks job run uses one job cluster for all tasks in that run (new
-- cluster on retry). Multiple Airflow-triggered jobs (e.g. parallel
-- execute-job-cluster-N) mean multiple clusters per logical DAG execution.
--
-- Source tables:
--   - system.lakeflow.job_task_run_timeline           (spine — per-task-run)
--   - system.lakeflow.job_run_timeline                (parent run state)
--   - system.compute.clusters                         (cluster spec — latest)
--   - system.billing.usage                            (DBU per cluster, hourly buckets)
--   - system.billing.list_prices                      (AWS USD list rate per DBU SKU)
--   - datalake_databricks_health.daily_cluster_health (PR 23079 — P50/P95 util, calculated EC2)
--   - datalake_databricks_health.spark_stage_metrics  (PR 23080 — per stage)
--
-- Cluster scope: all clusters that appear in Lakeflow task-run timeline for
-- the load window (latest snapshot from system.compute.clusters). No
-- provisioner or environment filter — covers bietlejuice, quintoml, CDP, and
-- other job workloads present in Lakeflow.
--
-- Cost attribution: system.billing.usage is hour-bucketed (usage_start_time at
-- HH:00:00). Joining billing rows to task time windows mis-attributes DBU.
-- We sum DBU and USD per (workspace_id, cluster_id) for the load window, then
-- allocate to tasks by each task's share of total task wall-clock seconds on
-- that cluster (equal split when all task durations are zero).
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
--   ended]. The dag_id key is aligned to COALESCE(cluster application tag,
--   billing job_name, cluster_name). Sequential-task DAGs usually match
--   uniquely. For DAGs with PARALLEL tasks of the same dag_id, the same
--   spark_app may match multiple task windows and the
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
            DATE(c.change_time) BETWEEN DATE_SUB(DATE('{load_start_date}'), 730) AND DATE('{load_end_date}')
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
run_clusters AS (
    SELECT DISTINCT
        workspace_id,
        cluster_id
    FROM
        task_run_spine
),
usage_for_run_clusters AS (
    SELECT
        u.workspace_id,
        u.usage_metadata.cluster_id                        AS cluster_id,
        u.sku_name,
        u.usage_quantity,
        u.usage_start_time,
        u.usage_metadata.job_name                          AS billing_job_name,
        COALESCE(p.unit_price_usd, 0)                      AS unit_price_usd
    FROM
        system.billing.usage u
    INNER JOIN
        run_clusters rc
            ON  rc.workspace_id              = u.workspace_id
            AND rc.cluster_id                = u.usage_metadata.cluster_id
    LEFT JOIN
        prices_per_sku p
            ON  p.sku_name           = u.sku_name
            AND u.usage_start_time  >= p.price_start_time
            AND (p.price_end_time IS NULL OR u.usage_start_time < p.price_end_time)
    WHERE
        u.usage_unit = 'DBU'
        AND DATE(u.usage_start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
sku_totals_by_cluster AS (
    SELECT
        workspace_id,
        cluster_id,
        sku_name,
        SUM(usage_quantity)                                AS sku_dbu
    FROM
        usage_for_run_clusters
    GROUP BY
        workspace_id, cluster_id, sku_name
),
cluster_primary_sku AS (
    SELECT
        workspace_id,
        cluster_id,
        MAX_BY(sku_name, sku_dbu)                          AS pricing_sku
    FROM
        sku_totals_by_cluster
    GROUP BY
        workspace_id, cluster_id
),
billing_per_cluster AS (
    SELECT
        ufr.workspace_id,
        ufr.cluster_id,
        SUM(ufr.usage_quantity)                            AS dbu_consumed,
        SUM(ufr.usage_quantity * ufr.unit_price_usd)       AS cost_usd_estimate,
        MAX_BY(ufr.billing_job_name, ufr.usage_quantity)    AS billing_job_name
    FROM
        usage_for_run_clusters ufr
    GROUP BY
        ufr.workspace_id, ufr.cluster_id
),
task_with_seconds AS (
    SELECT
        s.workspace_id,
        s.job_id,
        s.run_id,
        s.task_run_id,
        s.task_key,
        s.cluster_id,
        s.ts_task_started,
        s.ts_task_ended,
        s.setup_duration_seconds,
        s.task_result_state,
        s.dt_task_started,
        GREATEST(
            CAST(unix_timestamp(s.ts_task_ended) AS BIGINT)
            - CAST(unix_timestamp(s.ts_task_started) AS BIGINT),
            CAST(0 AS BIGINT)
        )                                                  AS task_seconds
    FROM
        task_run_spine s
),
cluster_task_seconds AS (
    SELECT
        workspace_id,
        cluster_id,
        SUM(task_seconds)                                  AS cluster_total_seconds
    FROM
        task_with_seconds
    GROUP BY
        workspace_id, cluster_id
),
tasks_per_cluster AS (
    SELECT
        workspace_id,
        cluster_id,
        COUNT(*)                                           AS n_tasks
    FROM
        task_with_seconds
    GROUP BY
        workspace_id, cluster_id
),
billing_per_task AS (
    SELECT
        t.workspace_id,
        t.run_id,
        t.task_run_id,
        COALESCE(CAST(bc.dbu_consumed AS DOUBLE), CAST(0 AS DOUBLE))
            * (
                CASE
                    WHEN COALESCE(cts.cluster_total_seconds, CAST(0 AS BIGINT)) > CAST(0 AS BIGINT)
                        THEN CAST(t.task_seconds AS DOUBLE) / CAST(cts.cluster_total_seconds AS DOUBLE)
                    WHEN COALESCE(tpc.n_tasks, 0) > 0
                        THEN 1.0 / CAST(tpc.n_tasks AS DOUBLE)
                    ELSE CAST(1 AS DOUBLE)
                END
            )                                              AS total_dbu_consumed,
        COALESCE(CAST(bc.cost_usd_estimate AS DOUBLE), CAST(0 AS DOUBLE))
            * (
                CASE
                    WHEN COALESCE(cts.cluster_total_seconds, CAST(0 AS BIGINT)) > CAST(0 AS BIGINT)
                        THEN CAST(t.task_seconds AS DOUBLE) / CAST(cts.cluster_total_seconds AS DOUBLE)
                    WHEN COALESCE(tpc.n_tasks, 0) > 0
                        THEN 1.0 / CAST(tpc.n_tasks AS DOUBLE)
                    ELSE CAST(1 AS DOUBLE)
                END
            )                                              AS total_dbu_cost_usd,
        (
            CASE
                WHEN COALESCE(cts.cluster_total_seconds, CAST(0 AS BIGINT)) > CAST(0 AS BIGINT)
                    THEN CAST(t.task_seconds AS DOUBLE) / CAST(cts.cluster_total_seconds AS DOUBLE)
                WHEN COALESCE(tpc.n_tasks, 0) > 0
                    THEN 1.0 / CAST(tpc.n_tasks AS DOUBLE)
                ELSE CAST(1 AS DOUBLE)
            END
        )                                                  AS task_weight,
        cps.pricing_sku,
        pr_eff.unit_price_usd                              AS dbu_rate_usd
    FROM
        task_with_seconds t
    LEFT JOIN
        cluster_task_seconds cts
            ON  cts.workspace_id = t.workspace_id
            AND cts.cluster_id   = t.cluster_id
    LEFT JOIN
        tasks_per_cluster tpc
            ON  tpc.workspace_id = t.workspace_id
            AND tpc.cluster_id   = t.cluster_id
    LEFT JOIN
        billing_per_cluster bc
            ON  bc.workspace_id = t.workspace_id
            AND bc.cluster_id   = t.cluster_id
    LEFT JOIN
        cluster_primary_sku cps
            ON  cps.workspace_id = t.workspace_id
            AND cps.cluster_id   = t.cluster_id
    LEFT JOIN
        prices_per_sku pr_eff
            ON  pr_eff.sku_name = cps.pricing_sku
            AND TIMESTAMP('{load_end_date}') >= pr_eff.price_start_time
            AND (pr_eff.price_end_time IS NULL OR TIMESTAMP('{load_end_date}') < pr_eff.price_end_time)
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
    LEFT JOIN
        billing_per_cluster bc_spark
            ON  bc_spark.workspace_id = s.workspace_id
            AND bc_spark.cluster_id   = s.cluster_id
    INNER JOIN
        stage_per_app spa
            ON  spa.dag_id               = COALESCE(
                    lcs.tags['application'],
                    bc_spark.billing_job_name,
                    lcs.cluster_name
                )
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

    -- Prefer cluster `dag_id` tag when present; else derive from application/billing/cluster_name.
    -- Raw billing/cluster names use hyphens + Airflow run suffixes (_scheduled__, etc.).
    -- Normalize to Airflow-style IDs (e.g. bietlejuice.core_brokers_history_dataset) when that pattern matches.
    CASE
        WHEN NULLIF(TRIM(COALESCE(lcs.tags['dag_id'], '')), '') IS NOT NULL
            THEN TRIM(lcs.tags['dag_id'])
        WHEN COALESCE(lcs.tags['application'], bc_dag.billing_job_name, lcs.cluster_name)
            RLIKE '.*(_scheduled__|_manual__|_dataset__|_dataset_triggered__).*'
        THEN
            regexp_replace(
                regexp_replace(
                    regexp_extract(
                        regexp_replace(
                            COALESCE(
                                lcs.tags['application'],
                                bc_dag.billing_job_name,
                                lcs.cluster_name
                            ),
                            '^job-[0-9]+-run-[0-9]+-',
                            ''
                        ),
                        '^(.*?)(?:_scheduled__|_manual__|_dataset__|_dataset_triggered__).*',
                        1
                    ),
                    '^bietlejuice-',
                    'bietlejuice.'
                ),
                '^quintoml-wonka-',
                'quintoml.wonka.'
            )
        ELSE COALESCE(lcs.tags['application'], bc_dag.billing_job_name, lcs.cluster_name)
    END                                                            AS airflow_dag_id,
    s.task_key                                                     AS airflow_task_id,
    -- Governance / attribution tags from cluster custom_tags when present
    -- (bietlejuice / framework-managed workloads). Other provisioners may leave
    -- these NULL — cost dashboards should tolerate NULL team_owner / cost_center.
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

    -- Wall-clock durations: the two headline numbers a developer looks at first.
    BIGINT(unix_timestamp(s.ts_task_ended) - unix_timestamp(s.ts_task_started))
                                                                   AS total_duration_seconds,
    BIGINT(unix_timestamp(s.ts_task_ended) - unix_timestamp(s.ts_task_started))
        - COALESCE(s.setup_duration_seconds, 0)                    AS execution_duration_seconds,

    -- CPU: driver then worker (P50 / P95 busy + wait).
    dch.p50_driver_cpu_busy_percent,
    dch.p95_driver_cpu_busy_percent,
    dch.p50_driver_cpu_wait_percent,
    dch.p95_driver_cpu_wait_percent,
    dch.p50_worker_cpu_busy_percent,
    dch.p95_worker_cpu_busy_percent,
    dch.p50_worker_cpu_wait_percent,
    dch.p95_worker_cpu_wait_percent,

    -- Memory: driver then worker (P50 / P95 used).
    dch.p50_driver_mem_used_percent,
    dch.p95_driver_mem_used_percent,
    dch.p50_worker_mem_used_percent,
    dch.p95_worker_mem_used_percent,

    -- Disk: /local_disk0 utilization (EBS-backed on standard instances; NVMe on d/i3/g5 families).
    dch.nvme_utilization_pct_p95                                    AS local_disk_utilization_pct_p95,

    -- Cost (DBU — system tables list price).
    CAST(ROUND(COALESCE(b.total_dbu_consumed, 0), 4) AS DECIMAL(25, 4))   AS total_dbu_consumed,
    CAST(ROUND(COALESCE(b.total_dbu_cost_usd, 0), 4) AS DECIMAL(37, 4))
                                                                   AS total_dbu_cost_usd,
    b.dbu_rate_usd,
    b.pricing_sku,
    CAST(ROUND(COALESCE(dch.total_ec2_cost_calculated_usd, 0) * COALESCE(b.task_weight, 1.0), 4) AS DECIMAL(38, 4))
                                                                   AS total_ec2_cost_calculated_usd,
    CAST(ROUND(COALESCE(dch.spot_hours, 0) * COALESCE(b.task_weight, 1.0), 4) AS DECIMAL(38, 4))    AS spot_hours,
    CAST(ROUND(COALESCE(dch.on_demand_hours, 0) * COALESCE(b.task_weight, 1.0), 4) AS DECIMAL(38, 4))
                                                                   AS on_demand_hours,
    -- Cost (Overwatch EC2 + legacy). Apportioned by task weight.
    CAST(ROUND(dch.total_ec2_cost_overwatch_usd * COALESCE(b.task_weight, 1.0), 4) AS DECIMAL(38, 4)) AS total_ec2_cost_overwatch_usd,
    CAST(ROUND(dch.total_dbu_cost_overwatch_usd * COALESCE(b.task_weight, 1.0), 4) AS DECIMAL(38, 4)) AS total_dbu_cost_overwatch_usd,
    -- Overwatch DBU + EC2 combined (legacy bill-allocation cross-check).
    CAST(
        ROUND(
            (COALESCE(CAST(dch.total_dbu_cost_overwatch_usd AS DOUBLE), CAST(0 AS DOUBLE))
            + COALESCE(CAST(dch.total_ec2_cost_overwatch_usd AS DOUBLE), CAST(0 AS DOUBLE)))
            * COALESCE(b.task_weight, 1.0),
            4
        ) AS DECIMAL(38, 4)
    )                                                              AS total_cost_overwatch_usd,
    -- System-tables DBU USD (total_dbu_cost_usd) + calculated EC2 (node_timeline × instancedetails).
    CAST(
        ROUND(
            COALESCE(CAST(b.total_dbu_cost_usd AS DOUBLE), CAST(0 AS DOUBLE))
            + (COALESCE(CAST(dch.total_ec2_cost_calculated_usd AS DOUBLE), CAST(0 AS DOUBLE)) * COALESCE(b.task_weight, 1.0)),
            4
        ) AS DECIMAL(38, 4)
    )                                                              AS total_cost_usd,

    -- Cluster flags.
    dch.is_photon,
    (
        COALESCE(lcs.worker_node_type, '') RLIKE 'd[.-]'
        OR COALESCE(lcs.driver_node_type, '') RLIKE 'd[.-]'
        OR COALESCE(lcs.worker_node_type, '') RLIKE '^(i[3-9]|g[4-5]|p[3-5]d|d[2-3])'
        OR COALESCE(lcs.driver_node_type, '') RLIKE '^(i[3-9]|g[4-5]|p[3-5]d|d[2-3])'
    )                                                              AS has_local_nvme,
    dch.is_pool_backed,

    -- State / quality flags.
    s.task_result_state = 'SUCCEEDED'                              AS is_success,
    s.task_result_state = 'FAILED'                                 AS is_failed,
    s.setup_duration_seconds > 90                                  AS is_pool_acquisition_slow,
    lcs.tags['sensitive-data'] = 'true'                            AS is_sensitive_data,
    sptc.workspace_id IS NOT NULL                                  AS has_stage_data,
    COALESCE(sptc.is_stage_attribution_ambiguous, FALSE)           AS is_stage_attribution_ambiguous,

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

    -- Detailed cluster-startup timing (cluster-day attributes — dedupe before summing).
    -- These are less frequently consulted; placed here so the headline metrics above are visible first.
    s.setup_duration_seconds,
    dch.pre_init_script_seconds,
    dch.init_script_seconds,
    dch.post_init_script_seconds,
    dch.cluster_startup_seconds,

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
    billing_per_cluster bc_dag
        ON  bc_dag.workspace_id = s.workspace_id
        AND bc_dag.cluster_id   = s.cluster_id
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
