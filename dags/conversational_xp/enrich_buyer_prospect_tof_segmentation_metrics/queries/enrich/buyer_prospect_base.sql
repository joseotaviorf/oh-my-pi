WITH conversion_events AS (
    SELECT
        p.id_prospect AS id_user,
        p.ts_event,
        LOWER(p.business_context) AS business_context,
        CASE
            WHEN p.event_name = 'USER FIRST ACTIVATION' THEN 'nbp'
            WHEN p.event_name IN ('USER RECOVERY', 'USER RECOVERY IN OTHER CITY GROUP') THEN 'rbp'
        END AS event_name,
        c.is_concierge_prospect
    FROM
        datalake_demand_flows.prospect_daily_results p
    LEFT JOIN
        datalake_search.concierge_demand c
        ON p.id_prospect = c.id_user
            AND p.id_visit = c.id_visit
            AND c.is_concierge_prospect = TRUE
            AND LOWER(c.business_context) = 'sale'
    WHERE
        MAKE_DATE(p.year, p.month, p.day) >= DATE_TRUNC('MONTH', DATE('{start_date}'))
        AND MAKE_DATE(p.year, p.month, p.day) < ADD_MONTHS(DATE_TRUNC('MONTH', DATE('{end_date}')), 1)
        AND LOWER(p.business_context) = 'sale'
        AND p.event_type = 'CONVERSION'
        AND p.event_name IN (
            'USER FIRST ACTIVATION',
            'USER RECOVERY',
            'USER RECOVERY IN OTHER CITY GROUP'
        )
),

deduped_users AS (
    SELECT
        id_user,
        ts_event,
        business_context,
        event_name,
        COALESCE(is_concierge_prospect, FALSE) AS is_concierge_prospect,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                DATE_TRUNC('month', ts_event)
            ORDER BY
                ts_event ASC
        ) AS rn
    FROM
        conversion_events
)

SELECT
    id_user,
    business_context,
    is_concierge_prospect,
    DATE_TRUNC('month', ts_event) AS dt_activation_month,
    ts_event AS ts_bp_activation,
    DATE_ADD(DATE(ts_event), {window_4w_days}) AS dt_window_4w_end,
    DATE_ADD(DATE(ts_event), {window_8w_days}) AS dt_window_8w_end,
    event_name,
    YEAR(dt_activation_month) AS year,
    MONTH(dt_activation_month) AS month,
    DAY(dt_activation_month) AS day
FROM
    deduped_users
WHERE
    rn = 1
