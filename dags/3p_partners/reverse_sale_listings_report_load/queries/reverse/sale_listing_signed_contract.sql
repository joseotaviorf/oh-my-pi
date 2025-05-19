SELECT
    UUID() AS id,
    CAST(fsde.sk_sale_demand_event AS STRING) AS business_id,
    fsde.sk_region AS location_id,
    fsde.sk_house AS property_id,
    COALESCE(dc.uuid_company, '1P') AS company_uuid,
    'SALE' AS business_context,
    dsa.sale_price_agreed::FLOAT AS contract_value,
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
JOIN
    dw_sale.dim_sale_agreement AS dsa
        ON dsa.sk_offer = fsde.sk_offer
WHERE
    MAKE_DATE(fsde.year, fsde.month, fsde.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND dset.event_name = 'SALE_AGREEMENT_SIGNED'