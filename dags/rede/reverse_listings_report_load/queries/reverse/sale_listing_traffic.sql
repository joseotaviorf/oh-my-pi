SELECT
    CONCAT(
        SUBSTRING(MD5(CAST(MIN(fsse.sk_event) AS STRING)), 1, 8), '-',
        SUBSTRING(MD5(CAST(MIN(fsse.sk_event) AS STRING)), 9, 4), '-',
        SUBSTRING(MD5(CAST(MIN(fsse.sk_event) AS STRING)), 13, 4), '-',
        SUBSTRING(MD5(CAST(MIN(fsse.sk_event) AS STRING)), 17, 4), '-',
        SUBSTRING(MD5(CAST(MIN(fsse.sk_event) AS STRING)), 21, 12)
    ) AS id,
    fsse.sk_house_region AS location_id,
    fsse.sk_house AS property_id,
    dc.uuid_company AS company_uuid,
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
    dw_rede.dim_company AS dc
        ON fsse.sk_company = dc.sk_company
WHERE
    dsset.business_context = 'sale'
    AND dsset.event_type = 'Listing Page Viewed'
    AND year = {year}
    AND month = {month}
    AND day = {day}
    AND dc.uuid_company IS NOT NULL
GROUP BY
    location_id,
    property_id,
    company_uuid,
    business_context,
    fsse.year,
    fsse.month,
    fsse.day