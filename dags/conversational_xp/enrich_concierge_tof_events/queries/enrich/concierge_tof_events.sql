WITH tof_events AS (
    SELECT
        id_event,
        id_user,
        id_person,
        event_name,
        GET_JSON_OBJECT(event_properties, '$.egw_session_id') AS id_session,
        TRY_CAST(
            GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT
        ) AS id_house,
        UPPER(
            GET_JSON_OBJECT(event_properties, '$.business_context')
        ) AS business_context,
        ts_event,
        DATE(ts_event) AS dt_event
    FROM
        datalake_cdp_clean.user_tracking_events
    WHERE
        event_date >= DATE_FORMAT(
            DATE_SUB(CURRENT_DATE(), {days_lookback_60} - 1),
            'yyyy-MM-dd'
        )
        AND event_date <= DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
        AND event_name IN (
            'search_page_viewed',
            'search_results_page_viewed',
            'listing_page_viewed',
            'listing_favorite_set',
            'schedule_page_viewed'
        )
        AND id_user IS NOT NULL
),
ranked_people AS (
    SELECT
        id_user,
        id_person,
        ROW_NUMBER() OVER (
            PARTITION BY id_user
            ORDER BY
                ts_event DESC,
                id_person DESC
        ) AS rn
    FROM
        tof_events
    WHERE
        id_person IS NOT NULL
),
person_by_user AS (
    SELECT
        id_user,
        id_person
    FROM
        ranked_people
    WHERE
        rn = 1
),
search_events AS (
    SELECT
        id_user,
        id_session,
        business_context,
        dt_event
    FROM
        tof_events
    WHERE
        event_name IN (
            'search_page_viewed',
            'search_results_page_viewed'
        )
),
search_rollups AS (
    SELECT
        id_user,
        COUNT(
            DISTINCT CASE
                WHEN dt_event >= DATE_SUB(
                    CURRENT_DATE(),
                    {days_lookback_7} - 1
                )
                THEN id_session
            END
        ) AS qty_search_sessions_7d,
        COUNT(DISTINCT id_session) AS qty_search_sessions_60d,
        COUNT(
            DISTINCT CASE
                WHEN business_context = 'RENT' THEN id_session
            END
        ) AS qty_search_rent_60d,
        COUNT(
            DISTINCT CASE
                WHEN business_context = 'SALE' THEN id_session
            END
        ) AS qty_search_sale_60d,
        MAX(dt_event) AS dt_last_search
    FROM
        search_events
    GROUP BY
        id_user
),
lpv_events AS (
    SELECT
        id_event,
        id_user,
        id_house,
        ts_event,
        dt_event
    FROM
        tof_events
    WHERE
        event_name = 'listing_page_viewed'
),
lpv_by_house_3d AS (
    SELECT
        id_user,
        id_house,
        COUNT(DISTINCT id_event) AS qty_lpv_house_3d
    FROM
        lpv_events
    WHERE
        dt_event >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_3} - 1
        )
        AND id_house IS NOT NULL
    GROUP BY
        id_user,
        id_house
),
lpv_rollups AS (
    SELECT
        id_user,
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
        ) AS qty_houses_lpv_3d
    FROM
        lpv_events
    GROUP BY
        id_user
),
ranked_lpv AS (
    SELECT
        id_user,
        id_house,
        ts_event,
        ROW_NUMBER() OVER (
            PARTITION BY id_user
            ORDER BY
                ts_event DESC,
                id_event DESC
        ) AS rn
    FROM
        lpv_events
    WHERE
        id_house IS NOT NULL
),
last_lpv AS (
    SELECT
        id_user,
        id_house AS id_house_last_lpv,
        ts_event AS ts_last_lpv
    FROM
        ranked_lpv
    WHERE
        rn = 1
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
favorite_events AS (
    SELECT
        id_event,
        id_user,
        id_house,
        ts_event,
        dt_event
    FROM
        tof_events
    WHERE
        event_name = 'listing_favorite_set'
        AND dt_event >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_7} - 1
        )
),
favorite_rollups AS (
    SELECT
        id_user,
        COUNT(
            DISTINCT CASE
                WHEN dt_event = CURRENT_DATE() THEN id_house
            END
        ) AS qty_favorites_1d,
        COUNT(DISTINCT id_house) AS qty_favorites_7d
    FROM
        favorite_events
    GROUP BY
        id_user
),
ranked_favorites AS (
    SELECT
        id_user,
        id_house,
        ROW_NUMBER() OVER (
            PARTITION BY id_user
            ORDER BY
                ts_event DESC,
                id_event DESC
        ) AS rn
    FROM
        favorite_events
    WHERE
        id_house IS NOT NULL
),
last_favorite AS (
    SELECT
        id_user,
        id_house AS id_house_last_favorite
    FROM
        ranked_favorites
    WHERE
        rn = 1
),
schedule_events AS (
    SELECT
        id_event,
        id_user,
        id_house,
        ts_event,
        dt_event
    FROM
        tof_events
    WHERE
        event_name = 'schedule_page_viewed'
        AND dt_event >= DATE_SUB(
            CURRENT_DATE(),
            {days_lookback_7} - 1
        )
),
schedule_rollups AS (
    SELECT
        id_user,
        COUNT(
            DISTINCT CASE
                WHEN dt_event = CURRENT_DATE() THEN id_event
            END
        ) AS qty_schedule_page_1d
    FROM
        schedule_events
    GROUP BY
        id_user
),
ranked_schedules AS (
    SELECT
        id_user,
        id_house,
        ROW_NUMBER() OVER (
            PARTITION BY id_user
            ORDER BY
                ts_event DESC,
                id_event DESC
        ) AS rn
    FROM
        schedule_events
    WHERE
        id_house IS NOT NULL
),
last_schedule AS (
    SELECT
        id_user,
        id_house AS id_house_last_schedule
    FROM
        ranked_schedules
    WHERE
        rn = 1
),
all_users AS (
    SELECT id_user FROM search_rollups
    UNION
    SELECT id_user FROM lpv_rollups
    UNION
    SELECT id_user FROM favorite_rollups
    UNION
    SELECT id_user FROM schedule_rollups
)
SELECT
    all_users.id_user,
    person_by_user.id_person,
    last_lpv.id_house_last_lpv,
    last_favorite.id_house_last_favorite,
    last_schedule.id_house_last_schedule,
    COALESCE(
        search_rollups.qty_search_sessions_7d,
        0
    ) AS qty_search_sessions_7d,
    COALESCE(
        search_rollups.qty_search_sessions_60d,
        0
    ) AS qty_search_sessions_60d,
    COALESCE(
        search_rollups.qty_search_rent_60d,
        0
    ) AS qty_search_rent_60d,
    COALESCE(
        search_rollups.qty_search_sale_60d,
        0
    ) AS qty_search_sale_60d,
    COALESCE(lpv_rollups.qty_lpv_3d, 0) AS qty_lpv_3d,
    COALESCE(
        lpv_rollups.qty_houses_lpv_3d,
        0
    ) AS qty_houses_lpv_3d,
    top_lpv_houses.array_id_house_top_5_lpv_3d,
    COALESCE(
        favorite_rollups.qty_favorites_1d,
        0
    ) AS qty_favorites_1d,
    COALESCE(
        favorite_rollups.qty_favorites_7d,
        0
    ) AS qty_favorites_7d,
    COALESCE(
        schedule_rollups.qty_schedule_page_1d,
        0
    ) AS qty_schedule_page_1d,
    search_rollups.dt_last_search,
    last_lpv.ts_last_lpv,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    all_users
LEFT JOIN
    person_by_user
        ON all_users.id_user = person_by_user.id_user
LEFT JOIN
    search_rollups
        ON all_users.id_user = search_rollups.id_user
LEFT JOIN
    lpv_rollups
        ON all_users.id_user = lpv_rollups.id_user
LEFT JOIN
    last_lpv
        ON all_users.id_user = last_lpv.id_user
LEFT JOIN
    top_lpv_houses
        ON all_users.id_user = top_lpv_houses.id_user
LEFT JOIN
    favorite_rollups
        ON all_users.id_user = favorite_rollups.id_user
LEFT JOIN
    last_favorite
        ON all_users.id_user = last_favorite.id_user
LEFT JOIN
    schedule_rollups
        ON all_users.id_user = schedule_rollups.id_user
LEFT JOIN
    last_schedule
        ON all_users.id_user = last_schedule.id_user
