WITH metric_period_process AS (
    SELECT DISTINCT
        mp.id AS id_metric_period,
        mp.metric AS metric_name,
        mp.dt_init AS dt_metric_period_started,
        mp.dt_end AS dt_metric_period_ended
    FROM
        datalake_tiers.metric_period AS mp
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON YEAR(ad.date) = mp.year
            AND MONTH(ad.date) = mp.month
    WHERE
        mp.status = "VALID"
        AND ad.date BETWEEN DATE_SUB(DATE('{load_start_date}'), 90)
            AND DATE('{load_end_date}')
),
simple_metrics AS (
    SELECT
        me.id_user,
        me.id_agent,
        me.uuid_person,
        me.id_metric_period,
        me.final_metric AS metric,
        COUNT(DISTINCT me.id_external_domain) AS value,
        me.is_valid,
        mp.dt_metric_period_started,
        mp.dt_metric_period_ended,
        CURRENT_DATE AS dt_last_processing
    FROM
        datalake_tiers.metric_events AS me
    JOIN
        metric_period_process AS mp
            ON mp.id_metric_period = me.id_metric_period
    WHERE 
        me.is_compound_metric_part IS FALSE
        AND me.is_cumulative_metric IS FALSE
    GROUP BY 1, 2, 3, 4, 5, 7, 8, 9, 10
),
cumulative_metrics AS (
    SELECT
        me.id_user,
        me.id_agent,
        me.uuid_person,
        me.id_metric_period,
        me.final_metric AS metric,
        SUM(COALESCE(me.cumulative_value, 0)) AS value,
        me.is_valid,
        mp.dt_metric_period_started,
        mp.dt_metric_period_ended,
        CURRENT_DATE AS dt_last_processing
    FROM
        datalake_tiers.metric_events AS me
    JOIN
        metric_period_process AS mp
            ON mp.id_metric_period = me.id_metric_period
    WHERE 
        me.is_compound_metric_part IS FALSE
        AND me.is_cumulative_metric IS TRUE
        AND (
            me.final_metric NOT IN (
                "VGV_ACQ",
                "VGV_CONV",
                "VGV_TOTAL",
                "VGV_EN_TOTAL",
                "VGV_EA_TOTAL"
            )
            OR (me.final_metric = "VGV_CONV" AND me.agent_profile = "AGENT")
            OR (
                me.final_metric = "VGV_EN_TOTAL"
                AND me.agent_profile = "NEGOTIATION_EXECUTIVE"
            )
            OR (
                me.final_metric = "VGV_EA_TOTAL"
                AND me.agent_profile = "ASSOCIATED_EXECUTIVE"
            )
            OR (me.final_metric = "VGV_ACQ" AND me.agent_profile = "CIQ")
            OR (me.final_metric = "VGV_TOTAL" AND me.agent_profile = "AGENT")
        )
    GROUP BY 1, 2, 3, 4, 5, 7, 8, 9, 10
),
combined_agent_performance AS (
    SELECT
        id_user,
        id_agent,
        uuid_person,
        id_metric_period,
        metric AS metric_name,
        value AS metric_value,
        is_valid,
        dt_metric_period_started,
        dt_metric_period_ended,
        dt_last_processing
    FROM simple_metrics
    UNION ALL
    SELECT
        id_user,
        id_agent,
        uuid_person,
        id_metric_period,
        metric AS metric_name,
        value AS metric_value,
        is_valid,
        dt_metric_period_started,
        dt_metric_period_ended,
        dt_last_processing
    FROM cumulative_metrics
),
-- Keep every valid/invalid row untouched; only add a is_valid=TRUE / 0 row for a
-- (id_user, id_metric_period, metric_name) key that has no TRUE row anywhere else
-- (i.e. the metric was computed but every event for it was invalid).
agent_performance_for_output AS (
    SELECT
        id_user,
        id_agent,
        uuid_person,
        id_metric_period,
        metric_name,
        metric_value,
        is_valid,
        dt_metric_period_started,
        dt_metric_period_ended,
        dt_last_processing
    FROM
        combined_agent_performance
    UNION ALL
    SELECT DISTINCT
        cap.id_user,
        cap.id_agent,
        cap.uuid_person,
        cap.id_metric_period,
        cap.metric_name,
        0 AS metric_value,
        TRUE AS is_valid,
        cap.dt_metric_period_started,
        cap.dt_metric_period_ended,
        cap.dt_last_processing
    FROM
        combined_agent_performance AS cap
    WHERE
        cap.is_valid IS FALSE
        AND NOT EXISTS (
            SELECT 1
            FROM combined_agent_performance AS valid_row
            WHERE valid_row.id_user = cap.id_user
                AND valid_row.id_metric_period = cap.id_metric_period
                AND valid_row.metric_name = cap.metric_name
                AND valid_row.is_valid IS TRUE
        )
),
earliest_agent_activation AS (
    SELECT
        ael.id_agent,
        MIN(ael.ts_occurred) AS ts_first_agent_activated
    FROM
        datalake_ebdb_clean.agent_event_log AS ael
    WHERE
        ael.id_capability IS NULL
        AND ael.event_type = 'AGENT_ACTIVATED'
    GROUP BY
        ael.id_agent
),
metric_period_bounds AS (
    SELECT
        MAX(mpp.dt_metric_period_started) AS dt_last_metric_period_started
    FROM
        metric_period_process AS mpp
),
agent_activation_months AS (
    SELECT
        eaa.id_agent,
        EXPLODE(
            SEQUENCE(
                DATE(DATE_TRUNC('MONTH', eaa.ts_first_agent_activated)),
                mpb.dt_last_metric_period_started,
                INTERVAL 1 MONTH
            )
        ) AS dt_metric_period_started
    FROM
        earliest_agent_activation AS eaa
    CROSS JOIN
        metric_period_bounds AS mpb
    WHERE
        mpb.dt_last_metric_period_started IS NOT NULL
        AND DATE(DATE_TRUNC('MONTH', eaa.ts_first_agent_activated))
            <= mpb.dt_last_metric_period_started
),
latest_agent_by_metric_period AS (
    SELECT
        mpp.id_metric_period,
        a.id_user,
        a.id_agent,
        a.uuid_person,
        mpp.metric_name,
        ROW_NUMBER() OVER (
            PARTITION BY a.id_user, mpp.id_metric_period
            ORDER BY IF(a.status = 'ACTIVE', 1, 0) DESC, a.ts_updated DESC
        ) = 1 AS is_latest,
        (
            a.status != "INACTIVE"
            OR (a.status == "INACTIVE" AND a.ts_last_status_changed >= ADD_MONTHS(mpp.dt_metric_period_ended, -6))
        ) AS is_status_valid_by_metric_period,
        mpp.dt_metric_period_started,
        mpp.dt_metric_period_ended,
        -- keeping partitions immutable for the merge pipeline (aligned with metric_events / agent_allocation)
        YEAR(mpp.dt_metric_period_started) AS year,
        MONTH(mpp.dt_metric_period_started) AS month,
        DAY(mpp.dt_metric_period_started) AS day
    FROM
        agent_activation_months AS aam
    JOIN
        metric_period_process AS mpp
            ON aam.dt_metric_period_started = mpp.dt_metric_period_started
    JOIN
        datalake_agent_accreditation.agent AS a
            ON a.id_agent = aam.id_agent
)
SELECT
    lmp.id_user,
    lmp.id_agent,
    lmp.uuid_person,
    lmp.id_metric_period,
    lmp.metric_name,
    COALESCE(cap.metric_value, 0) AS metric_value,
    COALESCE(cap.is_valid, TRUE) AS is_valid,
    lmp.dt_metric_period_started,
    lmp.dt_metric_period_ended,
    COALESCE(cap.dt_last_processing, CURRENT_DATE) AS dt_last_processing,
    -- keeping partitions immutable for the merge pipeline (aligned with metric_events / agent_allocation)
    lmp.year,
    lmp.month,
    lmp.day
FROM
    latest_agent_by_metric_period AS lmp
LEFT JOIN
    agent_performance_for_output AS cap
        ON cap.id_user = lmp.id_user
        AND cap.id_metric_period = lmp.id_metric_period
        AND cap.metric_name = lmp.metric_name
WHERE
    lmp.is_latest IS TRUE
    AND lmp.is_status_valid_by_metric_period IS TRUE
    AND lmp.id_user IS NOT NULL
