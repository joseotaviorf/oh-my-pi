-- ============================================================================
-- daily_cluster_health.sql
--
-- Per (id_cluster, dt_cluster_run) snapshot of cluster shape and resource
-- utilisation, sourced exclusively from Databricks system tables. One row
-- per cluster per UTC date the cluster had any node-timeline observations.
--
-- For multi-day clusters (interactive / long-running), expect one row per
-- date the cluster was alive on.
--
-- Source tables:
--   - system.compute.node_timeline       (per-minute CPU, mem, disk per node)
--   - system.compute.clusters            (cluster spec snapshots; latest row taken)
--   - datalake_databricks.daily_clusters (Overwatch-derived lifecycle: init script
--                                         timing and per-cluster DBU/EC2 cost in USD;
--                                         not surfaced by system tables)
--
-- Filters:
--   - tags['provisioner'] = 'bietlejuice'      (only framework-managed clusters)
--   - tags['environment'] = '{environment}'    (scope to local workspace)
-- ============================================================================
WITH latest_cluster_spec AS (
    SELECT
        cluster_id,
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
            ROW_NUMBER() OVER (PARTITION BY c.cluster_id ORDER BY c.change_time DESC) AS rn
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
node_observations AS (
    SELECT
        nt.cluster_id,
        nt.instance_id,
        nt.driver,
        nt.start_time,
        nt.end_time,
        nt.cpu_user_percent,
        nt.cpu_system_percent,
        nt.cpu_wait_percent,
        nt.mem_used_percent,
        nt.disk_free_bytes_per_mount_point['/local_disk0'] AS local_disk0_free_bytes,
        DATE(nt.start_time) AS dt_cluster_run
    FROM
        system.compute.node_timeline nt
    JOIN
        latest_cluster_spec lcs
            ON nt.cluster_id = lcs.cluster_id
    WHERE
        DATE(nt.start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
node_capacity AS (
    -- Per (cluster, node, day) NVMe capacity proxy: max free_bytes seen for that
    -- node (the node was almost-empty at boot). Only meaningful on `*d.*` shapes.
    SELECT
        cluster_id,
        instance_id,
        dt_cluster_run,
        MAX(local_disk0_free_bytes) AS local_disk0_capacity_bytes
    FROM
        node_observations
    WHERE
        local_disk0_free_bytes IS NOT NULL
    GROUP BY
        cluster_id,
        instance_id,
        dt_cluster_run
),
nvme_used_per_observation AS (
    SELECT
        n.cluster_id,
        n.dt_cluster_run,
        nc.local_disk0_capacity_bytes,
        nc.local_disk0_capacity_bytes - n.local_disk0_free_bytes AS local_disk0_used_bytes
    FROM
        node_observations n
    JOIN
        node_capacity nc
            ON  n.cluster_id     = nc.cluster_id
            AND n.instance_id    = nc.instance_id
            AND n.dt_cluster_run = nc.dt_cluster_run
    WHERE
        n.local_disk0_free_bytes IS NOT NULL
),
nvme_aggregated AS (
    SELECT
        cluster_id,
        dt_cluster_run,
        MAX(local_disk0_capacity_bytes)                       AS nvme_capacity_bytes_per_node,
        APPROX_PERCENTILE(local_disk0_used_bytes, 0.95)       AS p95_nvme_used_bytes_per_node,
        MAX(local_disk0_used_bytes)                           AS max_nvme_used_bytes_per_node,
        100.0 * APPROX_PERCENTILE(local_disk0_used_bytes, 0.95)
            / NULLIF(MAX(local_disk0_capacity_bytes), 0)      AS nvme_utilization_pct_p95
    FROM
        nvme_used_per_observation
    GROUP BY
        cluster_id,
        dt_cluster_run
),
driver_metrics AS (
    SELECT
        cluster_id,
        dt_cluster_run,
        APPROX_PERCENTILE(cpu_user_percent + cpu_system_percent, 0.50) AS p50_driver_cpu_busy_percent,
        APPROX_PERCENTILE(cpu_user_percent + cpu_system_percent, 0.95) AS p95_driver_cpu_busy_percent,
        APPROX_PERCENTILE(cpu_wait_percent,                       0.50) AS p50_driver_cpu_wait_percent,
        APPROX_PERCENTILE(cpu_wait_percent,                       0.95) AS p95_driver_cpu_wait_percent,
        APPROX_PERCENTILE(mem_used_percent,                       0.50) AS p50_driver_mem_used_percent,
        APPROX_PERCENTILE(mem_used_percent,                       0.95) AS p95_driver_mem_used_percent
    FROM
        node_observations
    WHERE
        driver = TRUE
    GROUP BY
        cluster_id,
        dt_cluster_run
),
worker_metrics AS (
    SELECT
        cluster_id,
        dt_cluster_run,
        APPROX_PERCENTILE(cpu_user_percent + cpu_system_percent, 0.50) AS p50_worker_cpu_busy_percent,
        APPROX_PERCENTILE(cpu_user_percent + cpu_system_percent, 0.95) AS p95_worker_cpu_busy_percent,
        APPROX_PERCENTILE(cpu_wait_percent,                       0.50) AS p50_worker_cpu_wait_percent,
        APPROX_PERCENTILE(cpu_wait_percent,                       0.95) AS p95_worker_cpu_wait_percent,
        APPROX_PERCENTILE(mem_used_percent,                       0.50) AS p50_worker_mem_used_percent,
        APPROX_PERCENTILE(mem_used_percent,                       0.95) AS p95_worker_mem_used_percent
    FROM
        node_observations
    WHERE
        driver = FALSE
    GROUP BY
        cluster_id,
        dt_cluster_run
),
worker_concurrency AS (
    SELECT
        cluster_id,
        dt_cluster_run,
        AVG(workers_in_minute) AS avg_concurrent_workers,
        MAX(workers_in_minute) AS peak_concurrent_workers
    FROM (
        SELECT
            cluster_id,
            DATE(start_time)                  AS dt_cluster_run,
            DATE_TRUNC('MINUTE', start_time)  AS minute_window,
            COUNT(DISTINCT instance_id)       AS workers_in_minute
        FROM
            node_observations
        WHERE
            driver = FALSE
        GROUP BY
            cluster_id,
            DATE(start_time),
            DATE_TRUNC('MINUTE', start_time)
    )
    GROUP BY
        cluster_id,
        dt_cluster_run
),
cluster_window AS (
    SELECT
        cluster_id,
        dt_cluster_run,
        MIN(start_time)                                                                AS ts_cluster_first_seen,
        MAX(end_time)                                                                  AS ts_cluster_last_seen,
        BIGINT((unix_timestamp(MAX(end_time)) - unix_timestamp(MIN(start_time))) / 60) AS cluster_uptime_minutes,
        -- Distinct minutes with at least one node observation. Robust to clusters
        -- that idle-shutdown then restart within the same day (autoscaled or
        -- interactive) — `cluster_uptime_minutes` overstates those because it
        -- spans the gap. Cost-per-minute calculations should normalise by this.
        COUNT(DISTINCT DATE_TRUNC('MINUTE', start_time))                               AS cluster_active_minutes,
        COUNT(*)                                                                       AS num_node_observations
    FROM
        node_observations
    GROUP BY
        cluster_id,
        dt_cluster_run
),
cluster_lifecycle AS (
    -- Per-cluster-day startup timing + Overwatch-derived cost. Source materialises
    -- INIT_SCRIPTS_STARTED / INIT_SCRIPTS_FINISHED / RUNNING events from
    -- overwatch.clusterstatefact, which is not surfaced by Databricks system tables.
    -- Bietlejuice scope is enforced naturally via the LEFT JOIN against
    -- latest_cluster_spec (which already filters tags['provisioner'] = 'bietlejuice').
    SELECT
        id_cluster,
        dt_cluster_run,
        seconds_cluster_started_to_init_scripts_started        AS pre_init_script_seconds,
        seconds_init_scripts_started_to_init_scripts_finished  AS init_script_seconds,
        seconds_init_scripts_finished_to_running_started       AS post_init_script_seconds,
        seconds_total_startup_time                             AS cluster_startup_seconds,
        total_dbu_cost                                         AS total_dbu_cost_overwatch_usd,
        total_ec2_cost                                         AS total_ec2_cost_overwatch_usd
    FROM
        datalake_databricks.daily_clusters
    WHERE
        dt_cluster_run BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    cw.cluster_id                                                                             AS id_cluster,
    lcs.tags['application']                                                                   AS dag_name,
    lcs.cluster_name,
    lcs.cluster_source,
    lcs.driver_node_type,
    lcs.worker_node_type,
    lcs.dbr_version,
    lcs.worker_count,
    lcs.min_autoscale_workers,
    lcs.max_autoscale_workers,
    ROUND(wc.avg_concurrent_workers, 2)                                                       AS avg_concurrent_workers,
    wc.peak_concurrent_workers,
    cw.cluster_uptime_minutes,
    cw.cluster_active_minutes,
    cl.pre_init_script_seconds,
    cl.init_script_seconds,
    cl.post_init_script_seconds,
    cl.cluster_startup_seconds,
    ROUND(dm.p50_driver_cpu_busy_percent, 2)                                                  AS p50_driver_cpu_busy_percent,
    ROUND(dm.p95_driver_cpu_busy_percent, 2)                                                  AS p95_driver_cpu_busy_percent,
    ROUND(dm.p50_driver_cpu_wait_percent, 3)                                                  AS p50_driver_cpu_wait_percent,
    ROUND(dm.p95_driver_cpu_wait_percent, 3)                                                  AS p95_driver_cpu_wait_percent,
    ROUND(dm.p50_driver_mem_used_percent, 2)                                                  AS p50_driver_mem_used_percent,
    ROUND(dm.p95_driver_mem_used_percent, 2)                                                  AS p95_driver_mem_used_percent,
    ROUND(wm.p50_worker_cpu_busy_percent, 2)                                                  AS p50_worker_cpu_busy_percent,
    ROUND(wm.p95_worker_cpu_busy_percent, 2)                                                  AS p95_worker_cpu_busy_percent,
    ROUND(wm.p50_worker_cpu_wait_percent, 3)                                                  AS p50_worker_cpu_wait_percent,
    ROUND(wm.p95_worker_cpu_wait_percent, 3)                                                  AS p95_worker_cpu_wait_percent,
    ROUND(wm.p50_worker_mem_used_percent, 2)                                                  AS p50_worker_mem_used_percent,
    ROUND(wm.p95_worker_mem_used_percent, 2)                                                  AS p95_worker_mem_used_percent,
    -- "driver hot, workers cold" first-glance signal. Positive = driver CPU is busier than
    -- workers at the 95th percentile, which usually means a serial driver-side bottleneck
    -- (Python UDFs, .toPandas(), large collect, .show(), large schema evolution, etc.) and
    -- the cluster's worker shape is over-provisioned relative to actual parallel work.
    -- Surface as its own column so it sorts well in dashboards.
    ROUND(dm.p95_driver_cpu_busy_percent - wm.p95_worker_cpu_busy_percent, 2)                 AS p95_driver_minus_worker_cpu_busy_percent,
    nm.nvme_capacity_bytes_per_node,
    nm.p95_nvme_used_bytes_per_node,
    nm.max_nvme_used_bytes_per_node,
    ROUND(nm.nvme_utilization_pct_p95, 2)                                                     AS nvme_utilization_pct_p95,
    cw.num_node_observations,
    -- Overwatch-derived total cost in USD per cluster-day; cross-check second source
    -- to the system-tables-derived `cost_usd_estimate` in dw_databricks_health.fact.
    ROUND(cl.total_dbu_cost_overwatch_usd, 4)                                                 AS total_dbu_cost_overwatch_usd,
    ROUND(cl.total_ec2_cost_overwatch_usd, 4)                                                 AS total_ec2_cost_overwatch_usd,
    lcs.dbr_version LIKE '%-photon-%'                                                         AS is_photon,
    (lcs.driver_instance_pool_id IS NOT NULL OR lcs.worker_instance_pool_id IS NOT NULL)      AS is_pool_backed,
    cw.ts_cluster_first_seen,
    cw.ts_cluster_last_seen,
    CURRENT_TIMESTAMP()                                                                       AS ts_load,
    cw.dt_cluster_run
FROM
    cluster_window     cw
JOIN
    latest_cluster_spec lcs
        ON cw.cluster_id = lcs.cluster_id
LEFT JOIN
    driver_metrics     dm
        ON  cw.cluster_id    = dm.cluster_id
        AND cw.dt_cluster_run = dm.dt_cluster_run
LEFT JOIN
    worker_metrics     wm
        ON  cw.cluster_id    = wm.cluster_id
        AND cw.dt_cluster_run = wm.dt_cluster_run
LEFT JOIN
    nvme_aggregated    nm
        ON  cw.cluster_id    = nm.cluster_id
        AND cw.dt_cluster_run = nm.dt_cluster_run
LEFT JOIN
    worker_concurrency wc
        ON  cw.cluster_id    = wc.cluster_id
        AND cw.dt_cluster_run = wc.dt_cluster_run
LEFT JOIN
    cluster_lifecycle  cl
        ON  cw.cluster_id    = cl.id_cluster
        AND cw.dt_cluster_run = cl.dt_cluster_run
