WITH listings AS (
    SELECT DISTINCT
        lbc.id_house,
        lbc.business_context,
        COALESCE(fhl.sk_region, fl.sk_region) AS sk_region,
        CASE
            WHEN lbc.status = 'PUBLISHED' THEN 'on-market'
            WHEN lbc.status != 'PUBLISHED' THEN 'off-market'
            ELSE NULL
        END AS house_status,
        dhl.house_total_area,
        dhl.house_bedrooms,
        dhl.house_neighborhood,
        CASE 
            WHEN LOWER(dhl.house_type) IN ('apartamento', 'studiooukitchenette') THEN 'apartamento' 
            WHEN LOWER(dhl.house_type) IN ('casa', 'casacondominio') THEN 'casa' 
        END AS house_type,
        CASE 
            WHEN lbc.business_context = 'RENT' THEN dhl.house_rent
            WHEN lbc.business_context = 'SALE' THEN fl.price
        END AS house_price,
        CASE 
            WHEN lbc.business_context = 'RENT' THEN (dhl.house_rent / NULLIF(dhl.house_total_area,0))
            WHEN lbc.business_context = 'SALE' THEN fl.price_m2
        END AS price_m2,
        CASE 
            WHEN lbc.business_context = 'RENT' AND fhl.days_listing_to_contract_signed >= 0 THEN days_listing_to_contract_signed
            WHEN lbc.business_context = 'SALE' AND ff.ts_sale_agreement_signed IS NOT NULL THEN DATEDIFF(dd.date, ff.ts_sale_agreement_signed)
        END AS days_to_contract_sign,
        dhl.house_condo,
        dhl.house_iptu,       
        lbc.status
    FROM datalake_ebdb_clean.listing_business_context lbc
    JOIN dw_public.dim_house_listing dhl
        ON lbc.id_house = dhl.id_house
    LEFT JOIN dw_public.fact_house_listings fhl
        ON dhl.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN dw_sale.fact_listings fl
        ON lbc.id_house = fl.sk_house
    LEFT JOIN dw_sale.fact_offers ff 
        ON ff.sk_house = lbc.id_house
    LEFT JOIN dw_public.dim_date dd
        ON dd.sk_date = fl.sk_last_publication_date        
    WHERE
        DATEDIFF(dhl.ts_house_update, CURRENT_DATE) <= 365
)

SELECT DISTINCT
    lr.id_house,
    lr.business_context,
    lr.sk_region,
    lr.house_neighborhood,
    s.house_status,
    s.house_price,
    s.price_m2,
    s.days_to_contract_sign,
    s.id_house AS id_house_similares,
    lr.status
FROM listings AS lr 
JOIN listings AS s
    ON s.sk_region = lr.sk_region
    AND s.house_type = lr.house_type
    AND s.house_bedrooms >= lr.house_bedrooms 
    AND s.id_house != lr.id_house
    AND s.house_total_area BETWEEN lr.house_total_area * 0.7 AND lr.house_total_area * 1.3
    AND s.business_context = lr.business_context