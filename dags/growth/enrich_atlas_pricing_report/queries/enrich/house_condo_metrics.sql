/*
We need to review the similarity criteria for listings. Currently, we are not considering
the 'business_context' column in our comparison. To address this, I'm cloning the 'similar_listings'
query table and modifying the join conditions to exclude this column.
*/
WITH listings AS (
    SELECT DISTINCT
        lbc.id_house,
        COALESCE(fhl.sk_region, fl.sk_region) AS sk_region,
        dhl.house_total_area,
        dhl.house_bedrooms,
        COALESCE(dr_fr.name,dr_fs.name) AS neighborhood,
        CASE
            WHEN LOWER(dhl.house_type) IN ('apartamento', 'studiooukitchenette') THEN 'apartamento'
            WHEN LOWER(dhl.house_type) IN ('casa', 'casacondominio') THEN 'casa'
        END AS house_type,
        dhl.house_condo,
        dhl.house_iptu
    FROM datalake_ebdb_clean.listing_business_context lbc
    JOIN dw_public.dim_house_listing dhl
        ON lbc.id_house = dhl.id_house
    LEFT JOIN dw_public.fact_house_listings fhl
        ON dhl.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN dw_sale.fact_listings fl
        ON lbc.id_house = fl.sk_house
    LEFT JOIN dw_public.dim_region dr_fr
        ON dr_fr.sk_region = fhl.sk_region
    LEFT JOIN dw_public.dim_region dr_fs
        ON dr_fs.sk_region = fl.sk_region
    WHERE
        DATEDIFF(dhl.ts_house_update, CURRENT_DATE) <= 365
),

similar_listings AS (
    SELECT DISTINCT
        lr.id_house,
        lr.neighborhood,
        s.house_condo,
        s.house_iptu
    FROM listings AS lr
    JOIN listings AS s
        ON s.sk_region = lr.sk_region
        AND s.house_type = lr.house_type
        AND s.house_bedrooms >= lr.house_bedrooms
        AND s.id_house != lr.id_house
        AND s.house_total_area BETWEEN lr.house_total_area * 0.7 AND lr.house_total_area * 1.3
)

SELECT
    id_house,
    neighborhood,
    APPROX_PERCENTILE(house_condo, 0.5) as condominium_price_median,
    APPROX_PERCENTILE(house_iptu, 0.5) as urban_property_tax_median
FROM similar_listings
GROUP BY 1,2
