SELECT
    UUID() AS id,
    CAST(MIN(fsse.sk_event) AS STRING) AS business_id,
    fsse.sk_house_region AS location_id,
    fsse.sk_house AS property_id,
    COALESCE(dc.uuid_company, '1P') AS company_uuid,
    UPPER(dsset.business_context) AS business_context,
    COUNT(*) AS traffic_count,
    MAX(ts_event) AS ts_event,
    fsse.year,
    fsse.month,
    fsse.day
FROM
    dw_public.fact_search_session_event AS fsse
JOIN
    dw_public.dim_search_session_event_type AS dsset
        ON fsse.sk_event_type = dsset.sk_event_type
JOIN
    dw_public.dim_company_3p_partners AS dc
        ON fsse.sk_company = dc.sk_company
WHERE
    MAKE_DATE(fsse.year, fsse.month, fsse.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND dsset.business_context = 'sale'
    AND dsset.event_type = 'Listing Page Viewed'
GROUP BY
    location_id,
    property_id,
    company_uuid,
    business_context,
    fsse.year,
    fsse.month,
    fsse.day