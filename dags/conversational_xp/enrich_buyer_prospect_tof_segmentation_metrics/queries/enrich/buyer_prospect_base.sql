WITH tof_users AS (
    SELECT
    s.id_user,
    s.ts_event,
    DATE_TRUNC('month', s.ts_event) AS dt_event_month,
    LOWER(s.business_context) AS business_context,
    'tof' AS event_name,
    ROW_NUMBER() OVER (
        PARTITION BY
            s.id_user,
            DATE_TRUNC('month', s.ts_event)
        ORDER BY
            s.ts_event ASC
    ) AS rn
    FROM datalake_amplitude_page_viewed_events.schedule_search_listing_events s
    WHERE
        MAKE_DATE(s.year, s.month, s.day) >= DATE_TRUNC('MONTH', DATE('{start_date}'))
        AND MAKE_DATE(s.year, s.month, s.day) < ADD_MONTHS(DATE_TRUNC('MONTH', DATE('{end_date}')), 1)
        AND DATE_TRUNC('month', s.ts_event) >= DATE_TRUNC('MONTH', DATE('{start_date}'))
        AND s.id_user is not null
        AND s.id_session is not null
        AND lower(s.business_context) = 'sale'
),

bp_users AS (
    SELECT
        p.id_prospect AS id_user,
        p.ts_event,
        DATE_TRUNC('month', p.ts_event) AS dt_event_month,
        LOWER(p.business_context) AS business_context,
        CASE
            WHEN p.event_name = 'USER FIRST ACTIVATION' THEN 'nbp'
            WHEN p.event_name IN ('USER RECOVERY', 'USER RECOVERY IN OTHER CITY GROUP') THEN 'rbp'
        END AS event_name,
        COALESCE(c.is_concierge_prospect, FALSE) AS is_concierge_prospect,
        ROW_NUMBER() OVER (
            PARTITION BY
                p.id_prospect,
                DATE_TRUNC('month', p.ts_event)
            ORDER BY
                p.ts_event ASC
        ) AS rn
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

all_users AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        ts_event,
        dt_event_month,
        event_name,
        1 as priority
    FROM
        bp_users
    WHERE
        bp_users.rn = 1
    UNION ALL
    SELECT
        id_user,
        business_context,
        FALSE AS is_concierge_prospect,
        ts_event,
        dt_event_month,
        event_name,
        2 as priority
    FROM
        tof_users
    WHERE
        tof_users.rn = 1
),

deduped_users AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        ts_event,
        dt_event_month,
        event_name,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                dt_event_month
            ORDER BY
                priority ASC
        ) AS rn
    FROM
        all_users
)

SELECT
    id_user,
    business_context,
    is_concierge_prospect,
    event_name,
    CASE
        WHEN event_name in ('nbp', 'rbp') THEN 'bp'
        WHEN event_name = 'tof' THEN 'tof'
        ELSE NULL
    END AS segment_type,
    ts_event as ts_activation,
    dt_event_month as dt_activation_month,
    DATE_ADD(DATE(ts_event), {window_4w_days}) AS dt_window_4w_end,
    DATE_ADD(DATE(ts_event), {window_8w_days}) AS dt_window_8w_end,
    YEAR(dt_event_month) AS year,
    MONTH(dt_event_month) AS month,
    DAY(dt_event_month) AS day
FROM deduped_users
WHERE rn = 1
