WITH base_search_events AS (
    SELECT
        id_amplitude,
        id_user,
        id_search,
        ids_search_results_list,
        'Server-Side Rendering (SSR)' AS search_rendering_type,
        business_context,
        utm_source,
        utm_medium,
        up_platform,
        referrer,
        search_query_context,
        search_location_slug,
        view_mode,
        sort_order,
        uri,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_search_page_viewed_events AS spv
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION ALL
    SELECT
        id_amplitude,
        id_user,
        id_search,
        ids_search_results_list,
        'Client Search' AS search_rendering_type,
        business_context,
        utm_source,
        utm_medium,
        up_platform,
        referrer,
        search_query_context,
        search_location_slug,
        view_mode,
        sort_order,
        uri,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_search_results_page_viewed_events AS spv
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
all_events AS (
    SELECT
        bse.id_amplitude,
        bse.id_user,
        bse.id_search,
        EXPLODE(bse.ids_search_results_list) AS id_house,
        'Search' AS event_type,
        bse.search_rendering_type,
        COALESCE(bse.business_context, 'N/A') AS business_context,
        COALESCE(bse.utm_source, 'N/A') AS utm_source,
        COALESCE(bse.utm_medium, 'N/A') AS utm_medium,
        COALESCE(bse.up_platform, 'N/A') AS platform,
        referrer,
        CASE
            WHEN r_equal.level = 'Cidade' THEN 'city'
            WHEN r_equal.level = 'SubRegiao' THEN 'neighborhood'
            WHEN RLIKE(bse.uri, 'imovel\/[-+]?[0-9]*\.?[0-9]+,[-+]?[0-9]*\.?[0-9]+') THEN 'coordinates'
            WHEN RLIKE(bse.search_location_slug, 'rua|praça|avenida|av\.\-|\-r\-|\-av\-|\-praca\-|alameda|estrada|r\.\-|al\.\-|av\-|av\.') THEN 'street'
            WHEN NULLIF(bse.search_query_context, 'unknown') IS NOT NULL THEN search_query_context
            WHEN r_like_city.slug IS NOT NULL THEN 'neighborhood'
            ELSE 'unknown'
        END AS search_location_type,
        COALESCE(view_mode, 'N/A') AS search_view_mode,
        COALESCE(sort_order, 'N/A') AS search_sort_order,
        bse.ts_event,
        bse.year,
        bse.month,
        bse.day
    FROM
        base_search_events AS bse
    LEFT JOIN
        datalake_ebdb_clean.region AS r_equal
            ON bse.search_location_slug = r_equal.slug
    LEFT JOIN
        datalake_ebdb_clean.region AS r_like_city
            ON bse.search_location_slug like ('%' || r_like_city.slug || '%')
            AND r_like_city.level = 'Cidade'
    UNION ALL
    SELECT
        id_amplitude,
        id_user,
        GET_JSON_OBJECT(event_properties, '$.search_id') AS id_search,
        ep_house_id AS id_house,
        'Listing Page Viewed' AS event_type,
        'N/A' AS search_rendering_type,
        COALESCE(business_context, 'N/A') AS business_context,
        COALESCE(utm_source, 'N/A') AS utm_source,
        COALESCE(utm_medium, 'N/A') AS utm_medium,
        COALESCE(up_platform, 'N/A') AS platform,
        referrer,
        'N/A' AS search_location_type,
        'N/A' AS search_view_mode,
        'N/A' AS search_sort_order,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
session_identification AS (
    SELECT
        *,
        LAG(business_context) OVER (PARTITION BY id_amplitude ORDER BY ts_event) AS previous_business_context,
        UNIX_TIMESTAMP(ts_event) - UNIX_TIMESTAMP(
            LAG(ts_event) OVER (PARTITION BY id_amplitude ORDER BY ts_event)
        ) > 5 * 60 AS has_been_more_than_5_min
    FROM
        all_events
)
SELECT
    id_amplitude,
    id_user,
    id_search,
    id_house,
    event_type,
    search_rendering_type,
    LOWER(business_context) AS business_context,
    utm_source,
    utm_medium,
    platform,
    -- The following expression removes anything that comes before ://, like https://, as well as www., and anything that comes after the first / or ?
    -- For example, https://www.youtube.com/watch would turn into youtube.com. This is useful to standardize websites and reduce the volume in the dimension table
    -- The exception, always treated first, is of domains with safeframe.googlesyndication.com. These are google owned domains which track ads, and each ad has a different url
    CASE
        WHEN referrer like '%safeframe.googlesyndication.com%' THEN 'safeframe.googlesyndication.com'
        WHEN RLIKE(referrer, '^[^\/]*:\/\/') -- Tests if the string starts with the pattern <anything>://, like http://
            THEN COALESCE(
                REPLACE(SPLIT(
                        SPLIT(referrer, '://')[1], -- https://www.youtube.com/watch -> www.youtube.com/watch
                        '/'
                    )[0], -- www.youtube.com/watch -> www.youtube.com
                    'www.', '' -- www.youtube.com -> youtube.com
                ),
                'N/A'
            )
        ELSE COALESCE(REPLACE(SPLIT(referrer, '/')[0], 'www.', ''), 'N/A')
    END AS base_referrer_url,
    search_location_type,
    search_view_mode,
    search_sort_order,
    COUNT_IF(
        previous_business_context IS DISTINCT FROM business_context
        OR has_been_more_than_5_min
    ) OVER (PARTITION BY id_amplitude, year, month, day ORDER BY ts_event) AS nr_session_for_user_on_day,
    ts_event,
    year,
    month,
    day
FROM
    session_identification