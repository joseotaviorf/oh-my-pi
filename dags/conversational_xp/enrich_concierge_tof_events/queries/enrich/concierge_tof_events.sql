WITH search_daily AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_device,
        id_session,
        business_context,
        dt_event,
        ts_event
    FROM
        datalake_search.concierge_tof_search_events
    WHERE
        MAKE_DATE(year, month, day) >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_60} - 1
        )
        AND MAKE_DATE(year, month, day) <= CURRENT_DATE()
),
search_sessions AS (
    SELECT
        id_user,
        id_session,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_person
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_person
                )
            END
        ) AS id_person,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_device
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_device
                )
            END
        ) AS id_device,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_event
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_person
                )
            END
        ) AS id_event_last_identified,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_event
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_device
                )
            END
        ) AS id_event_last_device,
        MAX(
            CASE
                WHEN business_context = 'RENT' THEN 1
                ELSE 0
            END
        ) = 1 AS has_rent,
        MAX(
            CASE
                WHEN business_context = 'SALE' THEN 1
                ELSE 0
            END
        ) = 1 AS has_sale,
        MAX(dt_event) AS dt_last_search,
        MAX(
            CASE
                WHEN id_person IS NOT NULL
                THEN ts_event
            END
        ) AS ts_last_identified,
        MAX(
            CASE
                WHEN id_device IS NOT NULL
                THEN ts_event
            END
        ) AS ts_last_device
    FROM
        search_daily
    GROUP BY
        id_user,
        id_session
),
search_rollups AS (
    SELECT
        id_user,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_person
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_last_identified,
                    id_event_last_identified,
                    id_person
                )
            END
        ) AS id_person,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_device
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_last_device,
                    id_event_last_device,
                    id_device
                )
            END
        ) AS id_device,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_event_last_identified
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_last_identified,
                    id_event_last_identified,
                    id_person
                )
            END
        ) AS id_event_last_identified,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_event_last_device
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_last_device,
                    id_event_last_device,
                    id_device
                )
            END
        ) AS id_event_last_device,
        COUNT(
            CASE
                WHEN dt_last_search >= DATE_SUB(
                    CURRENT_DATE(),
                    {days_lookback_7} - 1
                )
                THEN 1
            END
        ) AS qty_search_sessions_7d,
        COUNT(*) AS qty_search_sessions_60d,
        SUM(
            CASE
                WHEN has_rent THEN 1
                ELSE 0
            END
        ) AS qty_search_rent_60d,
        SUM(
            CASE
                WHEN has_sale THEN 1
                ELSE 0
            END
        ) AS qty_search_sale_60d,
        MAX(dt_last_search) AS dt_last_search,
        MAX(ts_last_identified) AS ts_last_identified,
        MAX(ts_last_device) AS ts_last_device
    FROM
        search_sessions
    GROUP BY
        id_user
),
lpv_daily AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_device,
        id_house,
        dt_event,
        ts_event
    FROM
        datalake_search.concierge_tof_lpv_events
    WHERE
        MAKE_DATE(year, month, day) >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_60} - 1
        )
        AND MAKE_DATE(year, month, day) <= CURRENT_DATE()
),
lpv_rollups AS (
    SELECT
        id_user,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_person
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_person
                )
            END
        ) AS id_person,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_device
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_device
                )
            END
        ) AS id_device,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_event
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_person
                )
            END
        ) AS id_event_last_identified,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_event
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_device
                )
            END
        ) AS id_event_last_device,
        MAX_BY(
            id_house,
            STRUCT(ts_event, id_event, id_house)
        ) AS id_house_last_lpv,
        COUNT(
            DISTINCT CASE
                WHEN dt_event >= DATE_SUB(
                    CURRENT_DATE(),
                    {days_lookback_3} - 1
                )
                THEN id_event
            END
        ) AS qty_lpv_3d,
        COUNT(
            DISTINCT CASE
                WHEN dt_event >= DATE_SUB(
                    CURRENT_DATE(),
                    {days_lookback_3} - 1
                )
                THEN id_house
            END
        ) AS qty_houses_lpv_3d,
        MAX(ts_event) AS ts_last_lpv,
        MAX(
            CASE
                WHEN id_person IS NOT NULL
                THEN ts_event
            END
        ) AS ts_last_identified,
        MAX(
            CASE
                WHEN id_device IS NOT NULL
                THEN ts_event
            END
        ) AS ts_last_device
    FROM
        lpv_daily
    GROUP BY
        id_user
),
lpv_by_house_3d AS (
    SELECT
        id_user,
        id_house,
        COUNT(DISTINCT id_event) AS qty_lpv_house_3d
    FROM
        lpv_daily
    WHERE
        dt_event >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_3} - 1
        )
    GROUP BY
        id_user,
        id_house
),
ranked_lpv_houses AS (
    SELECT
        id_user,
        id_house,
        ROW_NUMBER() OVER (
            PARTITION BY id_user
            ORDER BY
                qty_lpv_house_3d DESC,
                id_house DESC
        ) AS rn
    FROM
        lpv_by_house_3d
),
top_lpv_houses AS (
    SELECT
        id_user,
        CONCAT_WS(
            ',',
            SORT_ARRAY(
                COLLECT_LIST(CAST(id_house AS STRING))
            )
        ) AS array_id_house_top_5_lpv_3d
    FROM
        ranked_lpv_houses
    WHERE
        rn <= 5
    GROUP BY
        id_user
),
intent_daily AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_device,
        id_house,
        event_name,
        dt_event,
        ts_event
    FROM
        datalake_search.concierge_tof_intent_events
    WHERE
        MAKE_DATE(year, month, day) >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_60} - 1
        )
        AND MAKE_DATE(year, month, day) <= CURRENT_DATE()
),
intent_rollups AS (
    SELECT
        id_user,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_person
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_person
                )
            END
        ) AS id_person,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_device
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_device
                )
            END
        ) AS id_device,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_event
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_person
                )
            END
        ) AS id_event_last_identified,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_event
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_device
                )
            END
        ) AS id_event_last_device,
        MAX_BY(
            CASE
                WHEN
                    event_name = 'listing_favorite_set'
                    AND dt_event >= DATE_SUB(
                        CURRENT_DATE(),
                        {days_lookback_7} - 1
                    )
                THEN id_house
            END,
            CASE
                WHEN
                    event_name = 'listing_favorite_set'
                    AND dt_event >= DATE_SUB(
                        CURRENT_DATE(),
                        {days_lookback_7} - 1
                    )
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_house
                )
            END
        ) AS id_house_last_favorite,
        MAX_BY(
            CASE
                WHEN
                    event_name = 'schedule_page_viewed'
                    AND dt_event >= DATE_SUB(
                        CURRENT_DATE(),
                        {days_lookback_7} - 1
                    )
                THEN id_house
            END,
            CASE
                WHEN
                    event_name = 'schedule_page_viewed'
                    AND dt_event >= DATE_SUB(
                        CURRENT_DATE(),
                        {days_lookback_7} - 1
                    )
                THEN STRUCT(
                    ts_event,
                    id_event,
                    id_house
                )
            END
        ) AS id_house_last_schedule,
        COUNT(
            DISTINCT CASE
                WHEN
                    event_name = 'listing_favorite_set'
                    AND dt_event = CURRENT_DATE()
                THEN id_house
            END
        ) AS qty_favorites_1d,
        COUNT(
            DISTINCT CASE
                WHEN
                    event_name = 'listing_favorite_set'
                    AND dt_event >= DATE_SUB(
                        CURRENT_DATE(),
                        {days_lookback_7} - 1
                    )
                THEN id_house
            END
        ) AS qty_favorites_7d,
        COUNT(
            DISTINCT CASE
                WHEN
                    event_name = 'schedule_page_viewed'
                    AND dt_event = CURRENT_DATE()
                THEN id_event
            END
        ) AS qty_schedule_page_1d,
        MAX(
            CASE
                WHEN id_person IS NOT NULL
                THEN ts_event
            END
        ) AS ts_last_identified,
        MAX(
            CASE
                WHEN id_device IS NOT NULL
                THEN ts_event
            END
        ) AS ts_last_device
    FROM
        intent_daily
    GROUP BY
        id_user
),
identity_candidates AS (
    SELECT
        id_user,
        id_person,
        id_device,
        id_event_last_identified,
        id_event_last_device,
        ts_last_identified,
        ts_last_device
    FROM
        search_rollups
    UNION ALL
    SELECT
        id_user,
        id_person,
        id_device,
        id_event_last_identified,
        id_event_last_device,
        ts_last_identified,
        ts_last_device
    FROM
        lpv_rollups
    UNION ALL
    SELECT
        id_user,
        id_person,
        id_device,
        id_event_last_identified,
        id_event_last_device,
        ts_last_identified,
        ts_last_device
    FROM
        intent_rollups
),
user_identities AS (
    SELECT
        id_user,
        MAX_BY(
            CASE
                WHEN id_person IS NOT NULL
                THEN id_person
            END,
            CASE
                WHEN id_person IS NOT NULL
                THEN STRUCT(
                    ts_last_identified,
                    id_event_last_identified,
                    id_person
                )
            END
        ) AS id_person,
        MAX_BY(
            CASE
                WHEN id_device IS NOT NULL
                THEN id_device
            END,
            CASE
                WHEN id_device IS NOT NULL
                THEN STRUCT(
                    ts_last_device,
                    id_event_last_device,
                    id_device
                )
            END
        ) AS id_device
    FROM
        identity_candidates
    GROUP BY
        id_user
),
intent_members AS (
    -- Snapshot membership from intent is 7-day, matching the pre-refactor
    -- favorite_rollups / schedule_rollups windows. intent_rollups itself stays
    -- 60-day because identity resolution reads it; unioning it here would admit
    -- users whose only intent activity is older than 7 days, giving them a
    -- snapshot row with zero intent metrics.
    SELECT DISTINCT
        id_user
    FROM
        intent_daily
    WHERE
        dt_event >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_7} - 1
        )
),
all_users AS (
    SELECT id_user FROM search_rollups
    UNION
    SELECT id_user FROM lpv_rollups
    UNION
    SELECT id_user FROM intent_members
)
SELECT
    all_users.id_user,
    user_identities.id_person,
    user_identities.id_device,
    lpv_rollups.id_house_last_lpv,
    intent_rollups.id_house_last_favorite,
    intent_rollups.id_house_last_schedule,
    COALESCE(search_rollups.qty_search_sessions_7d, 0)
        AS qty_search_sessions_7d,
    COALESCE(search_rollups.qty_search_sessions_60d, 0)
        AS qty_search_sessions_60d,
    COALESCE(search_rollups.qty_search_rent_60d, 0)
        AS qty_search_rent_60d,
    COALESCE(search_rollups.qty_search_sale_60d, 0)
        AS qty_search_sale_60d,
    COALESCE(lpv_rollups.qty_lpv_3d, 0) AS qty_lpv_3d,
    COALESCE(lpv_rollups.qty_houses_lpv_3d, 0) AS qty_houses_lpv_3d,
    top_lpv_houses.array_id_house_top_5_lpv_3d,
    COALESCE(intent_rollups.qty_favorites_1d, 0) AS qty_favorites_1d,
    COALESCE(intent_rollups.qty_favorites_7d, 0) AS qty_favorites_7d,
    COALESCE(intent_rollups.qty_schedule_page_1d, 0)
        AS qty_schedule_page_1d,
    search_rollups.dt_last_search,
    lpv_rollups.ts_last_lpv,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    all_users
LEFT JOIN
    user_identities
        ON all_users.id_user = user_identities.id_user
LEFT JOIN
    search_rollups
        ON all_users.id_user = search_rollups.id_user
LEFT JOIN
    lpv_rollups
        ON all_users.id_user = lpv_rollups.id_user
LEFT JOIN
    top_lpv_houses
        ON all_users.id_user = top_lpv_houses.id_user
LEFT JOIN
    intent_rollups
        ON all_users.id_user = intent_rollups.id_user
