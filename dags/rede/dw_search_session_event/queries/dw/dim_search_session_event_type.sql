WITH combinations AS (
    SELECT DISTINCT
        event_type,
        business_context,
        utm_source,
        utm_medium,
        platform,
        base_referrer_url,
        search_rendering_type,
        search_location_type,
        search_view_mode,
        search_sort_order
    FROM
        datalake_search_session_event.search_session_event
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
last_sk_values AS (
    SELECT
        COALESCE(MAX(sk_event_type), 0) AS max_sk_event_type
    FROM
        dw_public.dim_search_session_event_type
)
SELECT
    COALESCE(dcet.sk_event_type, lsv.max_sk_event_type + MONOTONICALLY_INCREASING_ID() + 1) AS sk_event_type,
    event_type,
    business_context,
    utm_source,
    utm_medium,
    platform,
    base_referrer_url,
    search_rendering_type,
    search_location_type,
    search_view_mode,
    search_sort_order,
    COALESCE(dcet.ts_load, NOW()) AS ts_load
FROM
    combinations AS c,
    last_sk_values AS lsv
FULL OUTER JOIN
    dw_public.dim_search_session_event_type AS dcet
        USING (
            event_type,
            business_context,
            utm_source,
            utm_medium,
            platform,
            base_referrer_url,
            search_rendering_type,
            search_location_type,
            search_view_mode,
            search_sort_order
        )
