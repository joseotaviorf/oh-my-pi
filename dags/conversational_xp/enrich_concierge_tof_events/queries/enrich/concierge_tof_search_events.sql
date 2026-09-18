WITH search_events_ranked AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_anonymous AS id_device,
        GET_JSON_OBJECT(
            event_properties,
            '$.egw_session_id'
        ) AS id_session,
        UPPER(
            GET_JSON_OBJECT(event_properties, '$.business_context')
        ) AS business_context,
        ts_event,
        DATE(ts_event) AS dt_event,
        ROW_NUMBER() OVER (
            PARTITION BY id_event
            ORDER BY
                ts_event DESC,
                id_person DESC,
                id_anonymous DESC
        ) AS row_number
    FROM
        datalake_cdp_clean.user_tracking
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
        AND event_name IN (
            'search_page_viewed',
            'search_results_page_viewed'
        )
        AND id_user IS NOT NULL
),
search_events AS (
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
        search_events_ranked
    WHERE
        row_number = 1
        AND id_session IS NOT NULL
)
SELECT
    id_event,
    id_user,
    id_person,
    id_device,
    id_session,
    business_context,
    dt_event,
    ts_event,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM
    search_events
