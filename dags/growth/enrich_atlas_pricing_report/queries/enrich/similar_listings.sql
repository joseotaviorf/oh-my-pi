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
        COALESCE(dr_fr.name,dr_fs.name) AS neighborhood,
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
            WHEN lbc.business_context = 'SALE' AND ff.ts_sale_agreement_signed IS NOT NULL AND dd.date <= ff.ts_sale_agreement_signed
                THEN DATEDIFF(ff.ts_sale_agreement_signed,dd.date)
        END AS days_to_contract_sign,
        CASE
            WHEN lbc.business_context = 'RENT' AND fhl.days_listing_to_contract_signed >= 0 THEN dc.rent
            WHEN lbc.business_context = 'SALE' AND ff.ts_sale_agreement_signed IS NOT NULL AND dd.date <= ff.ts_sale_agreement_signed
                THEN sale_price_agreed
        END AS negotiated_price,
        CASE
            WHEN lbc.business_context = 'RENT' AND fhl.days_listing_to_contract_signed >= 0 THEN (dc.rent / NULLIF(dhl.house_total_area,0))
            WHEN lbc.business_context = 'SALE' AND ff.ts_sale_agreement_signed IS NOT NULL AND dd.date <= ff.ts_sale_agreement_signed
                THEN (ff.sale_price_agreed / NULLIF(dhl.house_total_area,0))
        END AS negotiated_price_m2,
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
        AND ff.ts_sale_agreement_signed IS NOT NULL
    LEFT JOIN dw_sale.fact_listing_sale_flows sf
        ON SUBSTRING(sf.sk_house_listing,0,9) = fl.sk_house
    LEFT JOIN dw_public.dim_date dd
        ON dd.sk_date = sf.sk_house_listing_date
    LEFT JOIN dw_public.dim_region dr_fr
        ON dr_fr.sk_region = fhl.sk_region
    LEFT JOIN dw_public.dim_region dr_fs
        ON dr_fs.sk_region = fl.sk_region
    LEFT JOIN dw_public.dim_contract dc
        ON fhl.sk_contract = dc.sk_contract
    WHERE
        DATEDIFF(dhl.ts_house_update, CURRENT_DATE) <= 365
)

SELECT DISTINCT
    lr.id_house,
    lr.business_context,
    lr.sk_region,
    lr.neighborhood,
    lr.house_bedrooms,
    lr.house_total_area,
    lr.house_type,
    s.id_house AS similar_id_house,
    s.status AS similar_status,
    s.house_status AS similar_house_status,
    s.house_price AS similar_house_price,
    s.price_m2 AS similar_price_m2,
    s.days_to_contract_sign AS similar_days_to_contract_sign,
    s.negotiated_price AS similar_negotiated_price,
    s.negotiated_price_m2 AS similar_negotiated_price_m2,
    s.neighborhood AS similar_neighborhood,
    s.house_bedrooms AS similar_house_bedrooms,
    s.house_total_area AS similar_house_total_area,
    s.house_type AS similar_house_type
FROM listings AS lr
JOIN listings AS s
    ON s.sk_region = lr.sk_region
    AND s.house_type = lr.house_type
    AND s.house_bedrooms BETWEEN lr.house_bedrooms - 1 AND lr.house_bedrooms + 1
    AND s.id_house != lr.id_house
    AND s.house_total_area BETWEEN lr.house_total_area * 0.7 AND lr.house_total_area * 1.3
    AND s.business_context = lr.business_context
