SELECT
    COALESCE(MONOTONICALLY_INCREASING_ID() * 100000000 + sse.year * 10000 + sse.month * 100 + sse.day) AS sk_event,
    dsset.sk_event_type,
    COALESCE(sse.id_amplitude, -1) AS sk_amplitude,
    COALESCE(sse.id_user, -1) AS sk_user,
    COALESCE(sse.id_house, -1) AS sk_house,
    COALESCE(h.id_region, -1) AS sk_house_region,
    COALESCE(cs_supply.sk_company, -1) AS sk_company,
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
    datalake_ebdb_clean.house AS h
        ON h.id = sse.id_house 
LEFT JOIN
    datalake_rede_house_history.rede_house_history AS rhh
        ON sse.id_house = rhh.id_house
        AND rhh.is_3p_supply
        AND UPPER(sse.business_context) = rhh.business_context
        AND sse.ts_event BETWEEN rhh.ts_status_started AND coalesce(rhh.ts_status_ended, now())
LEFT JOIN
    datalake_company.company_sks AS cs_supply
        ON (
            rhh.uuid_company IS NOT NULL
            AND rhh.uuid_company = cs_supply.uuid_company
        ) OR (
            rhh.uuid_company IS NULL
            AND rhh.id_company_hubspot IS NOT NULL
            AND rhh.id_company_hubspot = cs_supply.id_hubspot
        ) OR (
             rhh.uuid_company IS NULL
             AND rhh.id_company_hubspot IS NULL
             AND rhh.partner_3p_supply = cs_supply.extracted_3p_tag
        )
WHERE
    sse.year = {year}
    AND sse.month = {month}
    AND sse.day = {day}