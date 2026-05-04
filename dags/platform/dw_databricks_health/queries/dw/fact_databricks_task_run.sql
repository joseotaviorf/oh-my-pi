-- ============================================================================
-- fact_databricks_task_run.sql
--
-- Per Airflow-task-run health fact joining Databricks system tables with the
-- pre-aggregated cluster utilisation snapshot from
-- datalake_databricks_health.daily_cluster_health (PR 2 of the Phase 1.5
-- observability stack).
--
-- Grain: one row per
--   (id_databricks_workspace, id_databricks_run, id_databricks_task_run)
-- For the bietlejuice framework that is one row per Airflow task instance,
-- because query_delta DAGs spin up a job cluster per task.
--
-- Source tables:
--   - system.lakeflow.job_task_run_timeline   (spine — per-task-run, setup time)
--   - system.lakeflow.job_run_timeline        (parent run state, run_type)
--   - system.compute.clusters                 (cluster spec snapshots — latest)
--   - system.billing.usage                    (DBU per cluster-window)
--   - datalake_databricks_health.daily_cluster_health (PR 2 — P50/P95 util)
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
-- USD conversion is intentionally skipped in this version — system.billing.
-- usage exposes usage_quantity in DBUs but not the SKU rate. Joining
-- system.billing.list_prices to derive USD is left as a follow-up
-- enhancement.
--
-- Stage-level joins (PR 3 spark_stage_metrics, PR 4 sparkmeasure) are
-- intentionally deferred — see the DAG declaration documentation.
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
    -- Aggregate event-timeline rows down to one per task_run_id.
    -- job_task_run_timeline emits a new row every time a task transitions
    -- compute or status; we collapse the lifecycle here.
    SELECT
        workspace_id,
        job_id,
        run_id,
        task_run_id,
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
        workspace_id, job_id, run_id, task_run_id
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
billing_per_task AS (
    SELECT
        s.workspace_id,
        s.run_id,
        s.task_run_id,
        SUM(u.usage_quantity)                              AS dbu_consumed
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
    GROUP BY
        s.workspace_id, s.run_id, s.task_run_id
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
    -- mirrors `dags/platform/enrich_databricks/spark_jobs/{prod,forno}_conf.yml`.
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
    lcs.tags['dag_id']                                             AS airflow_dag_id,
    lcs.tags['task_id']                                            AS airflow_task_id,
    -- Governance / attribution tags. Set by the bietlejuice cluster builder; surfaced
    -- here as first-class columns so cost dashboards can group by team / cost center
    -- without re-parsing custom_tags. See bietlejuice/{prod,forno}_conf.yml
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
    -- Overwatch-derived cluster-day cost cross-check (USD). Same dedupe caveat as
    -- the *_script_seconds columns above — these are cluster-day, not task-run.
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

    s.task_result_state = 'SUCCEEDED'                              AS is_success,
    s.task_result_state = 'FAILED'                                 AS is_failed,
    dch.is_photon,
    dch.is_pool_backed,
    s.setup_duration_seconds > 90                                  AS is_pool_acquisition_slow,
    lcs.tags['sensitive-data'] = 'true'                            AS is_sensitive_data,

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
