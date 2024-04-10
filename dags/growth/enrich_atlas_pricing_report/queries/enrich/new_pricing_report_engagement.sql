WITH house_engagement AS (
    SELECT DISTINCT
        UNIX_TIMESTAMP(NOW()) AS ts_event,
        lbc.id_house::BIGINT,
        UPPER(lbc.business_context)::STRING AS business_context,
        COALESCE(pre.views_quantity, 0)::BIGINT AS views_quantity,
        COALESCE(pre.lpv_temperature_region_context, 'NO_VIEWS')::STRING AS demand_level,
        hm.condominium_price_median::BIGINT,
        hm.urban_property_tax_median::BIGINT,
        hm.on_market_price_median::BIGINT,
        ROUND(hm.on_market_price_by_square_meter::FLOAT,2) AS on_market_price_by_square_meter,
        hm.off_market_price_median::BIGINT,
        ROUND(hm.off_market_price_by_square_meter::FLOAT,2) AS off_market_price_by_square_meter,
        hm.negotiated_price_median::BIGINT,
        ROUND(hm.negotiated_price_by_square_meter::FLOAT,2) AS negotiated_price_by_square_meter,
        hm.median_days_to_contract_sign::BIGINT
    FROM datalake_ebdb_clean.listing_business_context lbc
    JOIN dw_public.dim_house_listing dhl
        ON lbc.id_house = dhl.id_house
    LEFT JOIN datalake_atlas_pricing_report.house_pricing_metrics hm
        ON lbc.id_house = hm.id_house
        AND LOWER(lbc.business_context) = LOWER(hm.business_context)
    LEFT JOIN datalake_atlas_pricing_report.house_listing_views_metrics pre
        ON lbc.id_house = pre.id_house::BIGINT
        AND LOWER(lbc.business_context) = LOWER(pre.business_context)
    WHERE
        DATEDIFF(dhl.ts_house_update, CURRENT_DATE) <= 365
        AND lbc.status IN ('PUBLISHED','SUSPENDED','UNPUBLISHED','OPTED_OUT') -- Tirar os casos de imóveis que ainda estão em edição e não fizeram FL
        AND dhl.country_code != 'MX'
)
SELECT
    ts_event AS ts_event,
    MONOTONICALLY_INCREASING_ID() AS id,
    id_house,
    business_context,
    views_quantity,
    demand_level,
    condominium_price_median,
    urban_property_tax_median,
    on_market_price_median,
    on_market_price_by_square_meter,
    off_market_price_median,
    off_market_price_by_square_meter,
    negotiated_price_median,
    negotiated_price_by_square_meter,
    median_days_to_contract_sign
FROM
    house_engagement
