WITH intent_events_ranked AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_anonymous AS id_device,
        event_name,
        TRY_CAST(
            GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT
        ) AS id_house,
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
            'listing_favorite_set',
            'schedule_page_viewed'
        )
        AND id_user IS NOT NULL
),
intent_events AS (
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
        intent_events_ranked
    WHERE
        row_number = 1
        AND id_house IS NOT NULL
)
SELECT
    id_event,
    id_user,
    id_person,
    id_device,
    id_house,
    event_name,
    dt_event,
    ts_event,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM
    intent_events
