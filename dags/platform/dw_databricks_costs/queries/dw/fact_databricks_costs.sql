-- ============================================================================
-- fact_databricks_costs.sql
--
-- Billing-spine daily cost fact — the all-workload COST AUTHORITY for the
-- Databricks + EC2 bill across every workspace (QuintoAndar, Prod, Forno) and
-- every compute type. Unlike dw_databricks_health.fact_databricks_task_run
-- (Airflow/Lakeflow job clusters only, ~80% DBU coverage), this fact starts
-- from `system.billing.usage` itself, so the sum of its DBU equals the billed
-- DBU universe BY CONSTRUCTION (~100% coverage incl. Forno).
--
-- Grain: one row per
--   (id_databricks_workspace, dt_usage, billing_origin_product, sku_name,
--    id_cluster, id_warehouse, id_databricks_job)
-- job_id is part of the grain so serverless / non-cluster usage keeps its job
-- identity and the per-job is_continuous flag stays unambiguous. A cluster
-- shared by several jobs yields one row per job on that cluster-day.
--
-- Net-of-record_type: Databricks corrections are additive, never in place. A
-- RETRACTION row carries a negative usage_quantity that cancels the ORIGINAL,
-- and a RESTATEMENT carries the corrected positive amount. SUM(usage_quantity)
-- across all record_type therefore yields the corrected net DBU; we never
-- dedupe on record_id. Groups that net to exactly zero are dropped (HAVING).
--
-- Bucket taxonomy (every billed product lands in exactly one bucket):
--   orchestrated_jobs  JOBS on real job clusters (Airflow / Lakeflow DAGs)
--   interactive        ALL_PURPOSE / INTERACTIVE, plus JOBS that ran on a
--                      UI/API-source (all-purpose) cluster (the "job on
--                      interactive" leak that inflates the health fact)
--   sql_warehouse      SQL warehouses (classic + serverless)
--   ml_serving         MODEL_SERVING / VECTOR_SEARCH / FOUNDATION_MODEL_TRAINING
--                      / AI_RUNTIME / AI_GATEWAY
--   streaming_dlt      DLT pipelines
--   platform_managed   PREDICTIVE_OPTIMIZATION / LAKEHOUSE_MONITORING /
--                      DATA_QUALITY_MONITORING / FINE_GRAINED_ACCESS_CONTROL /
--                      ONLINE_TABLES
--   apps_lakebase      APPS / DATABASE / CLEAN_ROOM
--   other              any product not yet mapped (residual confidence signal)
--
-- provisioner_resolved: best-effort attribution of who/what owns the workload.
-- Prefers the cluster `provisioner` tag; else infers from cluster_source
-- (UI/API => interactive) and name heuristics over `workload_name` (atlas/navent
-- => atlasdb, Overwatch => databricks-platform, batch-predict => quintoml-ml,
-- sandbox/test/poc/temp/fix => sandbox-test, known team keywords =>
-- team-workflow); unmatched => 'unresolved'.
--
-- DBU pricing — negotiated with list fallback. negotiated_usd_per_dbu comes
-- from datalake_databricks_pricing.dim_dbu_price keyed on compute_type and the
-- contract validity window [dt_valid_from, COALESCE(dt_valid_to, 9999-12-31)).
-- dbu_cost_usd = dbu * COALESCE(negotiated, list); dbu_list_cost_usd uses list
-- only (audit). When no negotiated rate matches (e.g. compute_type='OTHER'),
-- price_missing fires and the row falls back to list price — never a silent NULL.
--
-- EC2 cost — from system.compute.node_timeline node wall-clock hours priced by
-- datalake_databricks_pricing.dim_ec2_price (in-repo standard-AWS seed), split
-- on-demand vs spot from the cluster aws_attributes (availability +
-- first_on_demand). Before node_timeline history starts for each workspace, EC2
-- is estimated from datalake_databricks_usage_clean.billable_usage.machine_hours
-- where available. Source/confidence columns make this explicit.
--
-- Identity column is `workload_name` (NOT `airflow_dag_id`): this fact spans
-- non-Airflow workloads (interactive notebooks, SQL warehouses, model serving,
-- DLT, platform jobs), so the generic COALESCE(dag_id tag, application tag,
-- billing job_name, cluster_name) identity is correct here. The Airflow-DAG
-- normalisation lives in fact_databricks_task_run, which stays the operational
-- detail layer feeding dag_health.
--
-- Source tables:
--   - system.billing.usage             (spine — net DBU per grain)
--   - system.compute.clusters          (latest spec: tags, source, node types, aws_attributes)
--   - system.lakeflow.job_run_timeline (trigger_type => is_continuous)
--   - system.billing.list_prices       (AWS USD list rate per DBU SKU — audit + fallback)
--   - system.compute.node_timeline     (node wall-clock hours for EC2)
--   - datalake_databricks_usage_clean.billable_usage (EC2 estimate before
--                                                     node_timeline coverage)
--   - datalake_databricks_pricing.dim_dbu_price (negotiated USD/DBU by compute_type, window)
--   - datalake_databricks_pricing.dim_ec2_price  (standard USD/hour by instance, availability)
--
-- Reconciliation: a custom data-quality check
-- (data_quality/dw/fact_databricks_costs.yml) asserts that, for every
-- (workspace, dt_usage, billing_origin_product) present in the fact, SUM(dbu)
-- equals SUM(usage_quantity) net DBU in system.billing.usage for the same key
-- (|delta| <= 1.0 DBU). True by construction; the check guards against logic
-- regressions and late corrections drifting the totals.
-- ============================================================================
WITH billing AS (
    -- Spine: net DBU per grain (+ job_id) across all record_type.
    SELECT
        workspace_id,
        usage_date,
        billing_origin_product,
        sku_name,
        usage_metadata.cluster_id                                  AS cluster_id,
        usage_metadata.warehouse_id                                AS warehouse_id,
        usage_metadata.job_id                                      AS job_id,
        SUM(usage_quantity)                                        AS dbu,
        MAX(CASE WHEN UPPER(sku_name) LIKE '%SERVERLESS%' THEN 1 ELSE 0 END) = 1
                                                                   AS is_serverless,
        MAX_BY(usage_metadata.job_name, usage_quantity)            AS billing_job_name
    FROM
        system.billing.usage
    WHERE
        usage_unit = 'DBU'
        AND DATE(usage_date) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND workspace_id IN (4531937035440038, 6170817193817, 4033397625841925)
    GROUP BY
        workspace_id,
        usage_date,
        billing_origin_product,
        sku_name,
        usage_metadata.cluster_id,
        usage_metadata.warehouse_id,
        usage_metadata.job_id
    HAVING
        SUM(usage_quantity) <> 0
),
latest_cluster_spec AS (
    -- Latest cluster snapshot per (cluster_id, workspace_id) as of load_end_date.
    SELECT
        cluster_id,
        workspace_id,
        cluster_name,
        cluster_source,
        driver_node_type,
        worker_node_type,
        tags,
        cluster_availability,
        first_on_demand
    FROM (
        SELECT
            c.cluster_id,
            c.workspace_id,
            c.cluster_name,
            c.cluster_source,
            c.driver_node_type,
            c.worker_node_type,
            c.tags,
            CAST(
                FROM_JSON(TO_JSON(c.aws_attributes), 'map<string, string>')['availability'] AS STRING
            )                                                      AS cluster_availability,
            CAST(
                FROM_JSON(TO_JSON(c.aws_attributes), 'map<string, string>')['first_on_demand'] AS INT
            )                                                      AS first_on_demand,
            ROW_NUMBER() OVER (
                PARTITION BY c.cluster_id, c.workspace_id
                ORDER BY c.change_time DESC
            )                                                      AS rn
        FROM
            system.compute.clusters c
        WHERE
            DATE(c.change_time) <= DATE('{load_end_date}')
    )
    WHERE
        rn = 1
),
job_continuous AS (
    -- Continuous (streaming) jobs in the window, per (workspace, job).
    SELECT
        workspace_id,
        job_id,
        BOOL_OR(trigger_type = 'CONTINUOUS')                       AS is_continuous
    FROM
        system.lakeflow.job_run_timeline
    WHERE
        DATE(period_start_time) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        workspace_id,
        job_id
),
dbu_list_price AS (
    -- One list rate per SKU (AWS USD/DBU) whose validity overlaps the window.
    SELECT
        sku_name,
        MAX(pricing.default)                                       AS list_usd_per_dbu
    FROM
        system.billing.list_prices
    WHERE
        cloud             = 'AWS'
        AND usage_unit    = 'DBU'
        AND currency_code = 'USD'
        AND price_start_time <= TIMESTAMP('{load_end_date}')
        AND (price_end_time IS NULL OR price_end_time >= TIMESTAMP('{load_start_date}'))
    GROUP BY
        sku_name
),
node_observations AS (
    -- One row per node observation: wall-clock hours, instance type, availability.
    SELECT
        nt.workspace_id,
        nt.cluster_id,
        DATE(nt.start_time)                                        AS dt_cluster_run,
        (
            GREATEST(
                CAST(0 AS BIGINT),
                CAST(unix_timestamp(nt.end_time) AS BIGINT) - CAST(unix_timestamp(nt.start_time) AS BIGINT)
            ) / 3600.0
        )                                                          AS node_hours,
        IF(
            nt.driver = TRUE,
            lcs.driver_node_type,
            COALESCE(lcs.worker_node_type, lcs.driver_node_type)
        )                                                          AS instance_type,
        CASE
            -- Driver is on-demand when first_on_demand > 0 (job-cluster default);
            -- otherwise on-demand unless the cluster availability is SPOT.
            WHEN nt.driver = TRUE AND COALESCE(lcs.first_on_demand, 0) > 0
                THEN 'on_demand'
            WHEN UPPER(COALESCE(lcs.cluster_availability, 'ON_DEMAND')) LIKE '%SPOT%'
                THEN 'spot'
            ELSE 'on_demand'
        END                                                        AS availability
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
node_timeline_ec2_per_cluster_day AS (
    -- EC2 USD + on-demand/spot hours per (workspace, cluster, day), priced from
    -- the in-repo standard-AWS seed dim_ec2_price on (instance, availability, window).
    SELECT
        n.workspace_id,
        n.cluster_id,
        n.dt_cluster_run,
        SUM(n.node_hours * COALESCE(ep.usd_per_hour, 0))           AS ec2_cost_usd,
        SUM(IF(n.availability = 'on_demand', n.node_hours, 0))     AS on_demand_hours,
        SUM(IF(n.availability = 'spot', n.node_hours, 0))          AS spot_hours,
        'node_timeline'                                            AS ec2_source,
        FALSE                                                      AS is_ec2_estimated,
        BOOL_OR(ep.usd_per_hour IS NULL)                           AS ec2_pricing_missing,
        SUM(IF(ep.usd_per_hour IS NULL, n.node_hours, 0))          AS ec2_unpriced_hours
    FROM
        node_observations n
    LEFT JOIN
        datalake_databricks_pricing.dim_ec2_price ep
            ON  ep.instance_api_name = n.instance_type
            AND ep.availability      = n.availability
            AND n.dt_cluster_run    >= ep.dt_valid_from
            AND n.dt_cluster_run    <  COALESCE(ep.dt_valid_to, DATE '9999-12-31')
    GROUP BY
        n.workspace_id,
        n.cluster_id,
        n.dt_cluster_run
),
billable_usage_cluster_day AS (
    -- Pre-node_timeline EC2 estimate for 2026 continuity. The legacy table has
    -- QA/Prod machine hours only; do not synthesize Forno EC2.
    SELECT
        CAST(id_workspace AS BIGINT)                               AS workspace_id,
        id_cluster                                                 AS cluster_id,
        DATE(ts_execution)                                         AS dt_cluster_run,
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
billable_usage_ec2_per_cluster_day AS (
    -- Best-effort estimate: all billable_usage machine hours are priced as
    -- on-demand because the legacy source does not reliably expose spot split.
    SELECT
        bu.workspace_id,
        bu.cluster_id,
        bu.dt_cluster_run,
        SUM(bu.billable_usage_machine_hours * COALESCE(ep.usd_per_hour, 0))
                                                                   AS ec2_cost_usd,
        SUM(bu.billable_usage_machine_hours)                       AS on_demand_hours,
        CAST(0 AS DOUBLE)                                          AS spot_hours,
        'billable_usage_estimate'                                  AS ec2_source,
        TRUE                                                       AS is_ec2_estimated,
        BOOL_OR(ep.usd_per_hour IS NULL)                           AS ec2_pricing_missing,
        SUM(
            IF(ep.usd_per_hour IS NULL, bu.billable_usage_machine_hours, 0)
        )                                                          AS ec2_unpriced_hours
    FROM
        billable_usage_cluster_day bu
    LEFT JOIN
        datalake_databricks_pricing.dim_ec2_price ep
            ON  ep.instance_api_name = bu.billable_usage_node_type
            AND ep.availability      = 'on_demand'
            AND bu.dt_cluster_run   >= ep.dt_valid_from
            AND bu.dt_cluster_run   <  COALESCE(ep.dt_valid_to, DATE '9999-12-31')
    GROUP BY
        bu.workspace_id,
        bu.cluster_id,
        bu.dt_cluster_run
),
ec2_per_cluster_day AS (
    -- Prefer billable_usage for the pre-node_timeline backfill window when present;
    -- after that, node_timeline is authoritative and billable_usage is not loaded.
    SELECT
        COALESCE(nt.workspace_id, bu.workspace_id)                 AS workspace_id,
        COALESCE(nt.cluster_id, bu.cluster_id)                     AS cluster_id,
        COALESCE(nt.dt_cluster_run, bu.dt_cluster_run)             AS dt_cluster_run,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.ec2_cost_usd
            ELSE nt.ec2_cost_usd
        END                                                        AS ec2_cost_usd,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.on_demand_hours
            ELSE nt.on_demand_hours
        END                                                        AS on_demand_hours,
        CASE
            WHEN bu.cluster_id IS NOT NULL
                THEN bu.spot_hours
            ELSE nt.spot_hours
        END                                                        AS spot_hours,
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
            ELSE COALESCE(nt.ec2_unpriced_hours, 0)
        END                                                        AS ec2_unpriced_hours
    FROM
        node_timeline_ec2_per_cluster_day AS nt
    FULL OUTER JOIN
        billable_usage_ec2_per_cluster_day AS bu
            ON  nt.workspace_id   = bu.workspace_id
            AND nt.cluster_id     = bu.cluster_id
            AND nt.dt_cluster_run = bu.dt_cluster_run
),
enriched AS (
    -- Billing spine + cluster spec + continuity + list price + EC2; derive
    -- compute_type and the generic workload_name identity here so the
    -- dim_dbu_price join (keyed on compute_type) can run downstream. EC2 is at
    -- (workspace, cluster, day) grain and LEFT-joins onto every billing row of
    -- that cluster-day, so it is apportioned to each row by the row's DBU share
    -- of the cluster-day; the shares sum to 1, so SUM over the cluster-day
    -- equals the cluster-day EC2 total (no double counting above cluster-day
    -- grain). NULLIF guards a net-zero cluster-day; NULL cluster_id (serverless
    -- / warehouse) has no EC2 join and stays 0 downstream.
    SELECT
        b.workspace_id,
        b.usage_date,
        b.billing_origin_product,
        b.sku_name,
        b.cluster_id,
        b.warehouse_id,
        b.job_id,
        b.dbu,
        b.is_serverless,
        lcs.tags,
        lcs.cluster_name,
        lcs.cluster_source,
        jc.is_continuous,
        dlp.list_usd_per_dbu,
        ec.ec2_cost_usd
            * (b.dbu / NULLIF(SUM(b.dbu) OVER (PARTITION BY b.workspace_id, b.cluster_id, b.usage_date), 0))
                                                           AS ec2_cost_usd,
        ec.on_demand_hours
            * (b.dbu / NULLIF(SUM(b.dbu) OVER (PARTITION BY b.workspace_id, b.cluster_id, b.usage_date), 0))
                                                           AS on_demand_hours,
        ec.spot_hours
            * (b.dbu / NULLIF(SUM(b.dbu) OVER (PARTITION BY b.workspace_id, b.cluster_id, b.usage_date), 0))
                                                           AS spot_hours,
        CASE
            WHEN b.cluster_id IS NULL THEN 'not_applicable'
            WHEN ec.cluster_id IS NOT NULL THEN ec.ec2_source
            ELSE 'missing'
        END                                                        AS ec2_source,
        COALESCE(ec.is_ec2_estimated, FALSE)                       AS is_ec2_estimated,
        b.cluster_id IS NOT NULL AND COALESCE(ec.ec2_pricing_missing, FALSE)
                                                                   AS ec2_pricing_missing,
        ec.ec2_unpriced_hours
            * (b.dbu / NULLIF(SUM(b.dbu) OVER (PARTITION BY b.workspace_id, b.cluster_id, b.usage_date), 0))
                                                           AS ec2_unpriced_hours,
        COALESCE(
            NULLIF(TRIM(lcs.tags['dag_id']), ''),
            lcs.tags['application'],
            b.billing_job_name,
            lcs.cluster_name
        )                                                          AS workload_name,
        CASE
            WHEN b.billing_origin_product = 'JOBS'                       THEN 'JOBS'
            WHEN b.billing_origin_product IN ('ALL_PURPOSE', 'INTERACTIVE') THEN 'ALL_PURPOSE'
            WHEN b.billing_origin_product = 'SQL'                        THEN 'SQL'
            ELSE 'OTHER'
        END                                                        AS compute_type
    FROM
        billing b
    LEFT JOIN
        latest_cluster_spec lcs
            ON  lcs.cluster_id   = b.cluster_id
            AND lcs.workspace_id = b.workspace_id
    LEFT JOIN
        job_continuous jc
            ON  jc.workspace_id = b.workspace_id
            AND jc.job_id       = b.job_id
    LEFT JOIN
        dbu_list_price dlp
            ON dlp.sku_name = b.sku_name
    LEFT JOIN
        ec2_per_cluster_day ec
            ON  ec.workspace_id   = b.workspace_id
            AND ec.cluster_id     = b.cluster_id
            AND ec.dt_cluster_run = b.usage_date
),
priced AS (
    -- Apply negotiated DBU pricing (with list fallback) by compute_type + window.
    SELECT
        e.workspace_id,
        e.usage_date,
        e.billing_origin_product,
        e.sku_name,
        e.cluster_id,
        e.warehouse_id,
        e.job_id,
        e.dbu,
        e.is_serverless,
        e.tags,
        e.cluster_name,
        e.cluster_source,
        e.is_continuous,
        e.list_usd_per_dbu,
        e.ec2_cost_usd,
        e.on_demand_hours,
        e.spot_hours,
        e.ec2_source,
        e.is_ec2_estimated,
        e.ec2_pricing_missing,
        e.ec2_unpriced_hours,
        e.workload_name,
        e.compute_type,
        ddp.usd_per_dbu                                            AS negotiated_usd_per_dbu,
        ROUND(e.dbu * COALESCE(ddp.usd_per_dbu, e.list_usd_per_dbu), 4)
                                                                   AS dbu_cost_usd,
        ROUND(e.dbu * e.list_usd_per_dbu, 4)                       AS dbu_list_cost_usd,
        ddp.usd_per_dbu IS NULL                                    AS price_missing
    FROM
        enriched e
    LEFT JOIN
        datalake_databricks_pricing.dim_dbu_price ddp
            ON  ddp.compute_type = e.compute_type
            AND e.usage_date    >= ddp.dt_valid_from
            AND e.usage_date    <  COALESCE(ddp.dt_valid_to, DATE '9999-12-31')
)
SELECT
    -- Surrogate key over the full seven-key grain (job_id included so it is unique).
    XXHASH64(
        CAST(p.workspace_id AS STRING),
        CAST(p.usage_date AS STRING),
        p.billing_origin_product,
        p.sku_name,
        COALESCE(p.cluster_id, ''),
        COALESCE(p.warehouse_id, ''),
        COALESCE(CAST(p.job_id AS STRING), '')
    )                                                              AS sk_databricks_cost,

    -- Identifiers.
    p.workspace_id                                                AS id_databricks_workspace,
    p.cluster_id                                                  AS id_cluster,
    p.warehouse_id                                                AS id_warehouse,
    p.job_id                                                      AS id_databricks_job,

    -- Generic workload identity (spans non-Airflow workloads — NOT airflow_dag_id).
    p.workload_name,

    -- Characteristics.
    p.billing_origin_product,
    p.sku_name,
    p.cluster_source,
    p.cluster_name,
    p.compute_type,
    CASE
        WHEN p.compute_type IN ('JOBS', 'ALL_PURPOSE', 'SQL') THEN p.compute_type
        ELSE CONCAT('LIST_FALLBACK_', p.billing_origin_product)
    END                                                          AS pricing_category,
    CASE
        WHEN p.billing_origin_product = 'JOBS' AND p.cluster_source IN ('UI', 'API')
            THEN 'interactive'
        WHEN p.billing_origin_product = 'JOBS'
            THEN 'orchestrated_jobs'
        WHEN p.billing_origin_product IN ('ALL_PURPOSE', 'INTERACTIVE')
            THEN 'interactive'
        WHEN p.billing_origin_product = 'SQL'
            THEN 'sql_warehouse'
        WHEN p.billing_origin_product IN ('MODEL_SERVING', 'VECTOR_SEARCH', 'FOUNDATION_MODEL_TRAINING', 'AI_RUNTIME', 'AI_GATEWAY')
            THEN 'ml_serving'
        WHEN p.billing_origin_product = 'DLT'
            THEN 'streaming_dlt'
        WHEN p.billing_origin_product IN ('PREDICTIVE_OPTIMIZATION', 'LAKEHOUSE_MONITORING', 'DATA_QUALITY_MONITORING', 'FINE_GRAINED_ACCESS_CONTROL', 'ONLINE_TABLES')
            THEN 'platform_managed'
        WHEN p.billing_origin_product IN ('APPS', 'DATABASE', 'CLEAN_ROOM')
            THEN 'apps_lakebase'
        ELSE 'other'
    END                                                          AS bucket,
    CASE
        WHEN p.tags['provisioner'] IS NOT NULL
            THEN p.tags['provisioner']
        WHEN p.cluster_source IN ('UI', 'API')
            THEN 'interactive'
        WHEN LOWER(p.workload_name) RLIKE 'atlas|navent'
            THEN 'atlasdb'
        WHEN p.workload_name = 'Overwatch'
            THEN 'databricks-platform'
        WHEN p.workload_name = 'batch-predict'
            THEN 'quintoml-ml'
        WHEN LOWER(p.workload_name) RLIKE 'sandbox|teste|temp|test|poc|fix'
            THEN 'sandbox-test'
        WHEN LOWER(p.workload_name) RLIKE 'apura|fibonacci|rentflow|automa|listing|growth|capta|demand|metric|result|despublic|forms|skynet|concierge|iommi|amplitude'
            THEN 'team-workflow'
        ELSE 'unresolved'
    END                                                          AS provisioner_resolved,
    p.tags['owner']                                              AS team_owner,
    p.tags['cost-center']                                        AS cost_center,
    p.tags['ecosystem']                                         AS ecosystem,
    p.tags['environment']                                       AS environment,

    -- Metrics.
    CAST(ROUND(p.dbu, 4) AS DECIMAL(25, 4))                      AS dbu,
    p.negotiated_usd_per_dbu,
    p.dbu_cost_usd,
    p.dbu_list_cost_usd,
    ROUND(COALESCE(p.ec2_cost_usd, 0), 4)                       AS ec2_cost_usd,
    ROUND(COALESCE(p.on_demand_hours, 0), 4)                    AS on_demand_hours,
    ROUND(COALESCE(p.spot_hours, 0), 4)                         AS spot_hours,
    p.ec2_source,
    p.is_ec2_estimated,
    p.ec2_pricing_missing,
    ROUND(COALESCE(p.ec2_unpriced_hours, 0), 4)                 AS ec2_unpriced_hours,
    ROUND(p.dbu_cost_usd + COALESCE(p.ec2_cost_usd, 0), 4)      AS total_cost_usd,

    -- Booleans.
    p.is_serverless,
    COALESCE(p.is_continuous, FALSE)                            AS is_continuous,
    (p.billing_origin_product = 'JOBS' AND p.cluster_source IN ('UI', 'API'))
                                                                AS is_job_on_interactive,
    p.price_missing,

    -- Dates / timestamps.
    p.usage_date                                                AS dt_usage,
    CURRENT_TIMESTAMP()                                         AS ts_load,

    -- Partitions (last).
    YEAR(p.usage_date)                                          AS year,
    MONTH(p.usage_date)                                         AS month,
    DAY(p.usage_date)                                           AS day
FROM
    priced p
