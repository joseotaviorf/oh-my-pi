SELECT
    CONCAT(
        SUBSTRING(MD5(CAST(fsde.sk_sale_demand_event AS STRING)), 1, 8), '-',
        SUBSTRING(MD5(CAST(fsde.sk_sale_demand_event AS STRING)), 9, 4), '-',
        SUBSTRING(MD5(CAST(fsde.sk_sale_demand_event AS STRING)), 13, 4), '-',
        SUBSTRING(MD5(CAST(fsde.sk_sale_demand_event AS STRING)), 17, 4), '-',
        SUBSTRING(MD5(CAST(fsde.sk_sale_demand_event AS STRING)), 21, 12)
    ) AS id,
    fsde.sk_region AS location_id,
    fsde.sk_house AS property_id,
    dc.uuid_company AS company_uuid,
    'SALE' AS business_context,
    fsde.ts_event,
    fsde.year,
    fsde.month,
    fsde.day
FROM
    dw_sale.fact_sale_demand_event AS fsde
JOIN
    dw_sale.dim_sale_event_type AS dset
        ON fsde.sk_event_type = dset.sk_event_type
JOIN
    dw_rede.dim_company AS dc
        ON fsde.sk_company_supply = dc.sk_company
WHERE
    dset.event_name = 'OFFER_ACCEPTED'
    AND dc.uuid_company IS NOT NULL
    AND fsde.year = {year}
    AND fsde.month = {month}
    AND fsde.day = {day}
