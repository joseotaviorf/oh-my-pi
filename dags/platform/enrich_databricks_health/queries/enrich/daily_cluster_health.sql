-- ============================================================================
-- daily_cluster_health.sql
--
-- Per (id_databricks_workspace, id_cluster, dt_cluster_run) snapshot of cluster shape and resource
-- utilisation from Databricks system tables, augmented with Overwatch-derived
-- startup-timing rows from daily_clusters and EC2 USD priced from the
-- source-controlled standard-AWS seed datalake_databricks_pricing.dim_ec2_price.
-- One row per workspace/cluster per UTC date the cluster had node-timeline
-- observations or billable_usage machine-hour estimates before node_timeline
-- coverage begins for the workspace.
--
-- For multi-day clusters (interactive / long-running), expect one row per
-- date the cluster was alive on.
--
-- Source tables:
--   - system.compute.node_timeline       (per-minute CPU, mem, disk per node)
--   - system.compute.clusters            (cluster spec snapshots; latest row taken)
--   - datalake_databricks_usage_clean.billable_usage (EC2 estimate before
--                                         node_timeline coverage)
--   - datalake_databricks_pricing.dim_ec2_price (standard-AWS EC2 USD/hour per
--                                         instance + availability — same auditable
--                                         seed used by dw_databricks_costs.fact_databricks_costs)
--   - datalake_databricks.daily_clusters (Overwatch-derived lifecycle: init-script
--                                         startup timing not surfaced by system tables)
--
-- Cluster scope: all clusters present in system.compute.clusters (no provisioner
-- or environment tag filter). Aligns with dw_databricks_health.fact_databricks_task_run.
-- ============================================================================
WITH latest_cluster_spec AS (
    SELECT
        workspace_id,
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
        tags,
        CAST(
            FROM_JSON(TO_JSON(c.aws_attributes), 'map<string, string>')['availability'] AS STRING
        ) AS cluster_availability,
        CAST(
            FROM_JSON(TO_JSON(c.aws_attributes), 'map<string, string>')['first_on_demand'] AS INT
        ) AS first_on_demand
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
    ) AS c
    WHERE
        c.rn = 1
),
node_observations AS (
    SELECT
        nt.workspace_id,
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
            ON  nt.cluster_id   = lcs.cluster_id
            AND nt.workspace_id = lcs.workspace_id
    WHERE
        DATE(nt.start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
node_timeline_coverage AS (
    -- system.compute.node_timeline has rolling retention. Use the observed first
    -- available day per workspace instead of freezing the backfill boundary.
    SELECT
        CAST(workspace_id AS BIGINT) AS workspace_id,
        MIN(DATE(start_time))        AS dt_node_timeline_first_available
    FROM
        system.compute.node_timeline
    WHERE
        DATE(start_time) <= DATE('{load_end_date}')
        AND workspace_id IN (4531937035440038, 6170817193817)
    GROUP BY
        CAST(workspace_id AS BIGINT)
),
node_capacity AS (
    -- Per (cluster, node, day) NVMe capacity proxy: max free_bytes seen for that
    -- node (the node was almost-empty at boot). Only meaningful on `*d.*` shapes.
    SELECT
        workspace_id,
        cluster_id,
        instance_id,
        dt_cluster_run,
        MAX(local_disk0_free_bytes) AS local_disk0_capacity_bytes
    FROM
        node_observations
    WHERE
        local_disk0_free_bytes IS NOT NULL
    GROUP BY
        workspace_id,
        cluster_id,
        instance_id,
        dt_cluster_run
),
nvme_used_per_observation AS (
    SELECT
        n.workspace_id,
        n.cluster_id,
        n.dt_cluster_run,
        nc.local_disk0_capacity_bytes,
        nc.local_disk0_capacity_bytes - n.local_disk0_free_bytes AS local_disk0_used_bytes
    FROM
        node_observations n
    JOIN
        node_capacity nc
            ON  n.workspace_id   = nc.workspace_id
            AND n.cluster_id     = nc.cluster_id
            AND n.instance_id    = nc.instance_id
            AND n.dt_cluster_run = nc.dt_cluster_run
    WHERE
        n.local_disk0_free_bytes IS NOT NULL
),
nvme_aggregated AS (
    SELECT
        workspace_id,
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
        workspace_id,
        cluster_id,
        dt_cluster_run
),
driver_metrics AS (
    SELECT
        workspace_id,
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
        workspace_id,
        cluster_id,
        dt_cluster_run
),
worker_metrics AS (
    SELECT
        workspace_id,
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
        workspace_id,
        cluster_id,
        dt_cluster_run
),
worker_concurrency AS (
    SELECT
        workspace_id,
        cluster_id,
        dt_cluster_run,
        AVG(workers_in_minute) AS avg_concurrent_workers,
        MAX(workers_in_minute) AS peak_concurrent_workers
    FROM (
        SELECT
            workspace_id,
            cluster_id,
            DATE(start_time)                  AS dt_cluster_run,
            DATE_TRUNC('MINUTE', start_time)  AS minute_window,
            COUNT(DISTINCT instance_id)       AS workers_in_minute
        FROM
            node_observations
        WHERE
            driver = FALSE
        GROUP BY
            workspace_id,
            cluster_id,
            DATE(start_time),
            DATE_TRUNC('MINUTE', start_time)
    )
    GROUP BY
        workspace_id,
        cluster_id,
        dt_cluster_run
),
cluster_window AS (
    SELECT
        workspace_id,
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
        workspace_id,
        cluster_id,
        dt_cluster_run
),
cluster_lifecycle AS (
    -- Per-cluster-day startup timing + Overwatch-derived cost. Source materialises
    -- INIT_SCRIPTS_STARTED / INIT_SCRIPTS_FINISHED / RUNNING events from
    -- overwatch.clusterstatefact, which is not surfaced by Databricks system tables.
    -- Rows exist for any cluster-day present in daily_clusters for the load window.
    SELECT
        id_cluster,
        dt_cluster_run,
        seconds_cluster_started_to_init_scripts_started        AS pre_init_script_seconds,
        seconds_init_scripts_started_to_init_scripts_finished  AS init_script_seconds,
        seconds_init_scripts_finished_to_running_started       AS post_init_script_seconds,
        seconds_total_startup_time                             AS cluster_startup_seconds
    FROM
        datalake_databricks.daily_clusters
    WHERE
        dt_cluster_run BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
node_hours_priced AS (
    -- One row per node observation: wall-clock hours, instance type, availability.
    -- Mirrors dw_databricks_costs.fact_databricks_costs node_observations so both
    -- facts price EC2 from the same dim on identical keys.
    SELECT
        node_obs.workspace_id,
        node_obs.cluster_id,
        node_obs.dt_cluster_run,
        (
            GREATEST(
                CAST(0 AS BIGINT),
                CAST(unix_timestamp(node_obs.end_time) AS BIGINT) - CAST(unix_timestamp(node_obs.start_time) AS BIGINT)
            )
            / 3600.0
        )                                                          AS node_hours,
        IF(
            node_obs.driver = TRUE,
            latest_spec.driver_node_type,
            COALESCE(latest_spec.worker_node_type, latest_spec.driver_node_type)
        )                                                          AS instance_type,
        CASE
            -- Driver is on-demand when first_on_demand > 0 (job-cluster default);
            -- otherwise on-demand unless the cluster availability is SPOT.
            WHEN node_obs.driver = TRUE AND COALESCE(latest_spec.first_on_demand, 0) > 0
                THEN 'on_demand'
            WHEN UPPER(COALESCE(latest_spec.cluster_availability, 'ON_DEMAND')) LIKE '%SPOT%'
                THEN 'spot'
            ELSE 'on_demand'
        END                                                        AS availability
    FROM
        node_observations AS node_obs
    INNER JOIN
        latest_cluster_spec AS latest_spec
            ON  node_obs.cluster_id   = latest_spec.cluster_id
            AND node_obs.workspace_id = latest_spec.workspace_id
),
node_timeline_node_hours_cost AS (
    -- EC2 USD per (cluster, day) from node_timeline wall-clock hours priced by the
    -- in-repo standard-AWS seed dim_ec2_price on (instance, availability, window).
    -- Replaces the runtime overwatch.instancedetails dependency: on_demand rows are
    -- the same snapshot, spot = 0.37 x on-demand. NULL-priced instances contribute 0.
    SELECT
        priced_hours.workspace_id,
        priced_hours.cluster_id,
        priced_hours.dt_cluster_run,
        SUM(priced_hours.node_hours * COALESCE(ec2_price.usd_per_hour, CAST(0 AS DOUBLE)))
                                                                   AS total_ec2_cost_calculated_usd,
        SUM(IF(priced_hours.availability = 'spot', priced_hours.node_hours, CAST(0 AS DOUBLE)))
                                                                   AS ec2_spot_hours,
        SUM(IF(priced_hours.availability = 'on_demand', priced_hours.node_hours, CAST(0 AS DOUBLE)))
                                                                   AS ec2_on_demand_hours,
        'node_timeline'                                            AS ec2_source,
        FALSE                                                      AS is_ec2_estimated,
        BOOL_OR(ec2_price.usd_per_hour IS NULL)                    AS ec2_pricing_missing,
        SUM(IF(ec2_price.usd_per_hour IS NULL, priced_hours.node_hours, CAST(0 AS DOUBLE)))
                                                                   AS ec2_unpriced_hours
    FROM
        node_hours_priced AS priced_hours
    LEFT JOIN
        datalake_databricks_pricing.dim_ec2_price AS ec2_price
            ON  ec2_price.instance_api_name = priced_hours.instance_type
            AND ec2_price.availability      = priced_hours.availability
            AND priced_hours.dt_cluster_run >= ec2_price.dt_valid_from
            AND priced_hours.dt_cluster_run <  COALESCE(ec2_price.dt_valid_to, DATE '9999-12-31')
    GROUP BY
        priced_hours.workspace_id,
        priced_hours.cluster_id,
        priced_hours.dt_cluster_run
),
billable_usage_cluster_day AS (
    -- Legacy API dump used only for pre-node_timeline EC2 continuity. It has
    -- machine hours but no per-minute resource metrics.
    SELECT
        CAST(id_workspace AS BIGINT)                               AS workspace_id,
        id_cluster                                                 AS cluster_id,
        DATE(ts_execution)                                         AS dt_cluster_run,
        MAX(cluster_name)                                          AS billable_usage_cluster_name,
        MAX(cluster_node_type)                                     AS billable_usage_node_type,
        SUM(COALESCE(machine_hours, 0))                            AS billable_usage_machine_hours
    FROM
        datalake_databricks_usage_clean.billable_usage AS billable_usage
    LEFT JOIN
        node_timeline_coverage AS coverage
            ON CAST(billable_usage.id_workspace AS BIGINT) = coverage.workspace_id
    WHERE
        DATE(billable_usage.ts_execution) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND DATE(billable_usage.ts_execution) < COALESCE(
            coverage.dt_node_timeline_first_available,
            DATE_ADD(DATE('{load_end_date}'), 1)
        )
        AND machine_hours > 0
        AND id_workspace IN (4531937035440038, 6170817193817)
    GROUP BY
        CAST(id_workspace AS BIGINT),
        id_cluster,
        DATE(ts_execution)
),
billable_usage_node_hours_cost AS (
    SELECT
        bu.workspace_id,
        bu.cluster_id,
        bu.dt_cluster_run,
        SUM(bu.billable_usage_machine_hours * COALESCE(ec2_price.usd_per_hour, CAST(0 AS DOUBLE)))
                                                                   AS total_ec2_cost_calculated_usd,
        CAST(0 AS DOUBLE)                                          AS ec2_spot_hours,
        SUM(bu.billable_usage_machine_hours)                       AS ec2_on_demand_hours,
        'billable_usage_estimate'                                  AS ec2_source,
        TRUE                                                       AS is_ec2_estimated,
        BOOL_OR(ec2_price.usd_per_hour IS NULL)                    AS ec2_pricing_missing,
        SUM(
            IF(ec2_price.usd_per_hour IS NULL, bu.billable_usage_machine_hours, CAST(0 AS DOUBLE))
        )                                                          AS ec2_unpriced_hours
    FROM
        billable_usage_cluster_day AS bu
    LEFT JOIN
        datalake_databricks_pricing.dim_ec2_price AS ec2_price
            ON  ec2_price.instance_api_name = bu.billable_usage_node_type
            AND ec2_price.availability      = 'on_demand'
            AND bu.dt_cluster_run          >= ec2_price.dt_valid_from
            AND bu.dt_cluster_run          <  COALESCE(ec2_price.dt_valid_to, DATE '9999-12-31')
    GROUP BY
        bu.workspace_id,
        bu.cluster_id,
        bu.dt_cluster_run
),
node_hours_cost AS (
    SELECT
        COALESCE(nt.workspace_id, bu.workspace_id)                 AS workspace_id,
        COALESCE(nt.cluster_id, bu.cluster_id)                     AS cluster_id,
        COALESCE(nt.dt_cluster_run, bu.dt_cluster_run)             AS dt_cluster_run,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.total_ec2_cost_calculated_usd
            ELSE nt.total_ec2_cost_calculated_usd
        END                                                        AS total_ec2_cost_calculated_usd,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.ec2_spot_hours
            ELSE nt.ec2_spot_hours
        END                                                        AS ec2_spot_hours,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.ec2_on_demand_hours
            ELSE nt.ec2_on_demand_hours
        END                                                        AS ec2_on_demand_hours,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.ec2_source
            WHEN nt.cluster_id IS NOT NULL
                THEN nt.ec2_source
            WHEN bu.cluster_id IS NOT NULL THEN bu.ec2_source
            ELSE 'missing'
        END                                                        AS ec2_source,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.is_ec2_estimated
            ELSE COALESCE(nt.is_ec2_estimated, FALSE)
        END                                                        AS is_ec2_estimated,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.ec2_pricing_missing
            ELSE COALESCE(nt.ec2_pricing_missing, FALSE)
        END                                                        AS ec2_pricing_missing,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.ec2_unpriced_hours
            ELSE COALESCE(nt.ec2_unpriced_hours, CAST(0 AS DOUBLE))
        END                                                        AS ec2_unpriced_hours
    FROM
        node_timeline_node_hours_cost AS nt
    FULL OUTER JOIN
        billable_usage_node_hours_cost AS bu
            ON  nt.workspace_id    = bu.workspace_id
            AND nt.cluster_id      = bu.cluster_id
            AND nt.dt_cluster_run  = bu.dt_cluster_run
),
cluster_day_spine AS (
    SELECT DISTINCT
        workspace_id,
        cluster_id,
        dt_cluster_run
    FROM
        node_observations
    UNION
    SELECT DISTINCT
        workspace_id,
        cluster_id,
        dt_cluster_run
    FROM
        billable_usage_cluster_day
),
cluster_day_workspace_map AS (
    -- daily_clusters has no workspace id. Only attach its lifecycle metrics when
    -- a cluster-day maps to exactly one workspace in this table's output grain.
    SELECT
        cluster_id,
        dt_cluster_run,
        MAX(workspace_id) AS workspace_id
    FROM
        cluster_day_spine
    GROUP BY
        cluster_id,
        dt_cluster_run
    HAVING
        COUNT(DISTINCT workspace_id) = 1
),
cluster_lifecycle_with_workspace AS (
    SELECT
        workspace_map.workspace_id,
        cluster_lifecycle.id_cluster,
        cluster_lifecycle.dt_cluster_run,
        cluster_lifecycle.pre_init_script_seconds,
        cluster_lifecycle.init_script_seconds,
        cluster_lifecycle.post_init_script_seconds,
        cluster_lifecycle.cluster_startup_seconds
    FROM
        cluster_lifecycle
    INNER JOIN
        cluster_day_workspace_map AS workspace_map
            ON  cluster_lifecycle.id_cluster     = workspace_map.cluster_id
            AND cluster_lifecycle.dt_cluster_run = workspace_map.dt_cluster_run
)
SELECT
    cds.workspace_id                                                                          AS id_databricks_workspace,
    cds.cluster_id                                                                            AS id_cluster,
    lcs.tags['application']                                                                   AS dag_name,
    COALESCE(lcs.cluster_name, bu_cluster_day.billable_usage_cluster_name)                     AS cluster_name,
    lcs.cluster_source,
    COALESCE(lcs.driver_node_type, bu_cluster_day.billable_usage_node_type)                    AS driver_node_type,
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
    ROUND(COALESCE(nhc.total_ec2_cost_calculated_usd, CAST(0 AS DOUBLE)), 4)                  AS total_ec2_cost_calculated_usd,
    ROUND(COALESCE(nhc.ec2_spot_hours, CAST(0 AS DOUBLE)), 4)                                 AS ec2_spot_hours,
    ROUND(COALESCE(nhc.ec2_on_demand_hours, CAST(0 AS DOUBLE)), 4)                            AS ec2_on_demand_hours,
    COALESCE(nhc.ec2_source, 'missing')                                                       AS ec2_source,
    COALESCE(nhc.is_ec2_estimated, FALSE)                                                     AS is_ec2_estimated,
    COALESCE(nhc.ec2_pricing_missing, FALSE)                                                  AS ec2_pricing_missing,
    ROUND(COALESCE(nhc.ec2_unpriced_hours, CAST(0 AS DOUBLE)), 4)                             AS ec2_unpriced_hours,
    cw.cluster_id IS NOT NULL                                                                 AS has_node_timeline_metrics,
    COALESCE(lcs.dbr_version LIKE '%-photon-%', FALSE)                                        AS is_photon,
    COALESCE(
        lcs.driver_instance_pool_id IS NOT NULL OR lcs.worker_instance_pool_id IS NOT NULL,
        FALSE
    )                                                                                         AS is_pool_backed,
    cw.ts_cluster_first_seen,
    cw.ts_cluster_last_seen,
    CURRENT_TIMESTAMP()                                                                       AS ts_load,
    cds.dt_cluster_run
FROM
    cluster_day_spine AS cds
LEFT JOIN
    latest_cluster_spec AS lcs
        ON  cds.cluster_id   = lcs.cluster_id
        AND cds.workspace_id = lcs.workspace_id
LEFT JOIN
    billable_usage_cluster_day AS bu_cluster_day
        ON  cds.workspace_id    = bu_cluster_day.workspace_id
        AND cds.cluster_id      = bu_cluster_day.cluster_id
        AND cds.dt_cluster_run  = bu_cluster_day.dt_cluster_run
LEFT JOIN
    cluster_window AS cw
        ON  cds.workspace_id    = cw.workspace_id
        AND cds.cluster_id      = cw.cluster_id
        AND cds.dt_cluster_run  = cw.dt_cluster_run
LEFT JOIN
    driver_metrics     dm
        ON  cds.workspace_id    = dm.workspace_id
        AND cds.cluster_id      = dm.cluster_id
        AND cds.dt_cluster_run  = dm.dt_cluster_run
LEFT JOIN
    worker_metrics     wm
        ON  cds.workspace_id    = wm.workspace_id
        AND cds.cluster_id      = wm.cluster_id
        AND cds.dt_cluster_run  = wm.dt_cluster_run
LEFT JOIN
    nvme_aggregated    nm
        ON  cds.workspace_id    = nm.workspace_id
        AND cds.cluster_id      = nm.cluster_id
        AND cds.dt_cluster_run  = nm.dt_cluster_run
LEFT JOIN
    worker_concurrency wc
        ON  cds.workspace_id    = wc.workspace_id
        AND cds.cluster_id      = wc.cluster_id
        AND cds.dt_cluster_run  = wc.dt_cluster_run
LEFT JOIN
    cluster_lifecycle_with_workspace AS cl
        ON  cds.workspace_id    = cl.workspace_id
        AND cds.cluster_id      = cl.id_cluster
        AND cds.dt_cluster_run  = cl.dt_cluster_run
LEFT JOIN
    node_hours_cost nhc
        ON  cds.workspace_id    = nhc.workspace_id
        AND cds.cluster_id      = nhc.cluster_id
        AND cds.dt_cluster_run  = nhc.dt_cluster_run
