SELECT DISTINCT
    lbc.id_house,
    lbc.business_context,
    COALESCE(pre.views_quantity, 0) AS views_quantity,
    COALESCE(pre.lpv_temperature_region_context, 'NO VIEWS') AS demand_level,
    hm.condominium_price_median,
    hm.urban_property_tax_median,
    hm.on_mkt.on_market_price_median,
    hm.on_mkt.on_market_price_by_square_meter,
    hm.off_mkt.off_market_price_median,
    hm.off_mkt.off_market_price_by_square_meter,
    hm.median_days_to_contract_sign
FROM datalake_ebdb_clean.listing_business_context lbc
JOIN dw_public.dim_house_listing dhl
    ON lbc.id_house = dhl.id_house
LEFT JOIN datalake_atlas_pricing_report.house_pricing_metrics hm
    ON lbc.id_house = hm.id_house
    AND LOWER(lbc.business_context) = LOWER(hm.business_context)
LEFT JOIN datalake_atlas_pricing_report.house_listing_views_metrics pre
    ON lbc.id_house = pre.id_house
    AND LOWER(lbc.business_context) = LOWER(pre.business_context)
WHERE
    DATEDIFF(dhl.ts_house_update, CURRENT_DATE) <= 365
    AND lbc.status IN ('PUBLISHED','SUSPENDED','UNPUBLISHED','OPTED_OUT') -- Tirar os casos de imóveis que ainda estão em edição e não fizeram FL
    AND dhl.country_code != 'MX'