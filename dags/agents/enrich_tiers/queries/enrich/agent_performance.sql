WITH metric_period_process AS (
    SELECT DISTINCT
        mp.id AS id_metric_period,
        mp.dt_init AS dt_metric_period_started,
        mp.dt_end AS dt_metric_period_ended
    FROM
        datalake_tiers.metric_period AS mp
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN mp.dt_init AND mp.dt_end
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND mp.status = "VALID"
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
    GROUP BY ALL
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
    GROUP BY ALL
),
compound_metrics AS (
    SELECT
        me.id_user,
        me.id_agent,
        me.uuid_person,
        me.id_metric_period,
        me.partial_metric,
        me.final_metric AS metric,
        COUNT(DISTINCT me.id_external_domain) AS value,
        me.is_valid,
        mp.dt_metric_period_started,
        mp.dt_metric_period_ended
    FROM
        datalake_tiers.metric_events AS me
    JOIN
        metric_period_process AS mp
            ON mp.id_metric_period = me.id_metric_period
    WHERE 
        me.is_valid IS TRUE
        AND me.is_compound_metric_part IS TRUE
        AND me.is_cumulative_metric IS FALSE
    GROUP BY ALL
),
BP2CCV_compound_metric AS (
    SELECT
        cm.id_user,
        cm.id_agent,
        cm.uuid_person,
        cm.id_metric_period,
        cm.metric,
        CASE
            WHEN COALESCE(cm.value/ cms.value, 0) > 1 THEN 1
            ELSE ROUND(COALESCE(cm.value/ cms.value, 0), 2)
        END AS value,
        cm.is_valid,
        cm.dt_metric_period_started,
        cm.dt_metric_period_ended,
        CURRENT_DATE AS dt_last_processing
    FROM
        compound_metrics AS cm
    LEFT JOIN
        compound_metrics AS cms
            ON cms.id_user = cm.id_user
            AND cms.id_metric_period = cm.id_metric_period
            AND cms.partial_metric = "BP"
            AND cms.metric = "BP2CCV"
    WHERE
        cm.partial_metric = "CCV"
        AND cm.metric = "BP2CCV"
    GROUP BY ALL
),
TP2CS_compound_metric AS (
    SELECT
        cm.id_user,
        cm.id_agent,
        cm.uuid_person,
        cm.id_metric_period,
        cm.metric,
        CASE
            WHEN COALESCE(cm.value/ cms.value, 0) > 1 THEN 1
            ELSE ROUND(COALESCE(cm.value/ cms.value, 0), 2)
        END AS value,
        cm.is_valid,
        cm.dt_metric_period_started,
        cm.dt_metric_period_ended,
        CURRENT_DATE AS dt_last_processing
    FROM
        compound_metrics AS cm
    LEFT JOIN
        compound_metrics AS cms
            ON cms.id_user = cm.id_user
            AND cms.id_metric_period = cm.id_metric_period
            AND cms.partial_metric = "TP"
            AND cms.metric = "TP2CS"
    WHERE
        cm.partial_metric = "CS"
        AND cm.metric = "TP2CS"
    GROUP BY ALL
),
OS2CCV_BY_compound_metric AS (
    SELECT
        cm.id_user,
        cm.id_agent,
        cm.uuid_person,
        cm.id_metric_period,
        cm.metric,
        CASE
            WHEN COALESCE(cm.value/ cms.value, 0) > 1 THEN 1
            ELSE ROUND(COALESCE(cm.value/ cms.value, 0), 2)
        END AS value,
        cm.is_valid,
        cm.dt_metric_period_started,
        cm.dt_metric_period_ended,
        CURRENT_DATE AS dt_last_processing
    FROM
        compound_metrics AS cm
    LEFT JOIN
        compound_metrics AS cms
            ON cms.id_user = cm.id_user
            AND cms.id_metric_period = cm.id_metric_period
            AND cms.partial_metric = "OS"
            AND cms.metric = "OS2CCV_BY"
    WHERE
        cm.partial_metric = "CCV"
        AND cm.metric = "OS2CCV_BY"
    GROUP BY ALL
)
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
FROM BP2CCV_compound_metric
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
FROM TP2CS_compound_metric
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
FROM OS2CCV_BY_compound_metric