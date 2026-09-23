SELECT
    COALESCE(MONOTONICALLY_INCREASING_ID() * 100000000 + sse.year * 10000 + sse.month * 100 + sse.day) AS sk_event,
    dsset.sk_event_type,
    COALESCE(sse.id_amplitude, -1) AS sk_amplitude,
    COALESCE(sse.id_user, -1) AS sk_user,
    COALESCE(sse.id_house, -1) AS sk_house,
    COALESCE(h.id_region, -1) AS sk_house_region,
    COALESCE(
        CASE
            WHEN UPPER(sse.business_context) = 'SALE' AND h.is_sale_3p_supply THEN cb_supply.sk_broker
            WHEN UPPER(sse.business_context) = 'RENT' AND h.is_rent_3p_supply THEN cb_supply.sk_broker
        END,
        -1
    ) AS sk_broker,
    sse.id_amplitude * 100 + sse.nr_session_for_user_on_day AS sk_session,
    COALESCE(sse.id_search, -1) AS sk_search,
    COALESCE(BIGINT(DATE_FORMAT(sse.ts_event, 'yyyyMMdd')), -1) AS sk_event_date,
    sse.nr_session_for_user_on_day,
    sse.ts_event,
    sse.year,
    sse.month,
    sse.day
FROM
    datalake_search_session_event.search_session_event AS sse
JOIN
    dw_public.dim_search_session_event_type AS dsset
        USING(
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
JOIN
    datalake_ebdb_listing.house AS h
        ON h.id = sse.id_house
LEFT JOIN
    core_brokers.brokers AS cb_supply
        ON cb_supply.uuid_company = h.uuid_company
WHERE
    sse.year = {year}
    AND sse.month = {month}
    AND sse.day = {day}