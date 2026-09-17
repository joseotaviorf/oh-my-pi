WITH lpv_events AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_anonymous AS id_device,
        FROM_JSON(
            event_properties,
            'STRUCT<business_context:STRING, utm_source:STRING, utm_medium:STRING, house_id:STRING>'
        ) AS event_properties_parsed,
        egw_utm_source,
        egw_utm_medium,
        ts_event,
        DATE(ts_event) AS dt_event
    FROM
        datalake_cdp_clean.user_tracking
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
        AND event_name = 'listing_page_viewed'
        AND id_user IS NOT NULL
),
lpv_parsed AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_device,
        CASE
            WHEN event_properties_parsed.house_id LIKE '%.%'
            THEN NULL
            ELSE TRY_CAST(event_properties_parsed.house_id AS BIGINT)
        END AS id_house,
        LOWER(event_properties_parsed.business_context) AS business_context,
        LOWER(
            COALESCE(
                NULLIF(event_properties_parsed.utm_source, ''),
                egw_utm_source
            )
        ) AS utm_source,
        LOWER(
            COALESCE(
                NULLIF(event_properties_parsed.utm_medium, ''),
                egw_utm_medium
            )
        ) AS utm_medium,
        ts_event,
        dt_event,
        ROW_NUMBER() OVER (
            PARTITION BY id_event
            ORDER BY
                ts_event DESC,
                id_person DESC,
                id_device DESC
        ) AS row_number
    FROM
        lpv_events
),
lpv_deduplicated AS (
    SELECT
        id_event,
        id_user,
        id_person,
        id_device,
        id_house,
        business_context,
        utm_source,
        utm_medium,
        dt_event,
        ts_event
    FROM
        lpv_parsed
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
    business_context,
    utm_source,
    utm_medium,
    dt_event,
    ts_event,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(dt_event) AS year,
    MONTH(dt_event) AS month,
    DAY(dt_event) AS day
FROM
    lpv_deduplicated
