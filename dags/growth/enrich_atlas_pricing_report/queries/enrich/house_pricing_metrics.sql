WITH house_on_market_median_prices AS (
    SELECT
        id_house,
        business_context,
        house_neighborhood,
        house_status,
        APPROX_PERCENTILE(house_price, 0.5) AS on_market_price_median,
        APPROX_PERCENTILE(price_m2, 0.5) AS on_market_price_by_square_meter
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE status = 'PUBLISHED'
    GROUP BY 1,2,3,4
),

house_off_market_median_prices AS (
    SELECT
        id_house,
        business_context,
        house_neighborhood,
        house_status,
        APPROX_PERCENTILE(house_price, 0.5) AS off_market_price_median,
        APPROX_PERCENTILE(price_m2, 0.5) AS off_market_price_by_square_meter
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE status != 'PUBLISHED'
    GROUP BY 1,2,3,4
),

house_off_market_median_days_to_contract_sign AS (
    SELECT
        id_house,
        business_context,
        house_neighborhood,
        APPROX_PERCENTILE(days_to_contract_sign, 0.5) AS median_days_to_contract_sign
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE
        status != 'PUBLISHED'
        AND (days_to_contract_sign IS NULL OR days_to_contract_sign > 0)
    GROUP BY 1, 2, 3
)

SELECT 
    l.id_house,
    l.business_context,
    l.house_neighborhood,
    l.house_status,    
    hon.on_market_price_median,
    hon.on_market_price_by_square_meter,
    hoff.off_market_price_median,
    hoff.off_market_price_by_square_meter,
    hcs.median_days_to_contract_sign,
    hic.condominium_price_median,
    hic.urban_property_tax_median
FROM
    datalake_atlas_pricing_report.similar_listings l
LEFT JOIN
    house_on_market_median_prices hon
ON
    l.id_house = hon.id_house
    AND l.business_context = hon.business_context
    AND l.house_neighborhood = hon.house_neighborhood
    AND l.house_status = hon.house_status
LEFT JOIN
    house_off_market_median_prices hoff
ON
    l.id_house = hoff.id_house
    AND l.business_context = hoff.business_context
    AND l.house_neighborhood = hoff.house_neighborhood
    AND l.house_status = hoff.house_status
LEFT JOIN
    house_off_market_median_days_to_contract_sign hcs
ON
    l.id_house = hcs.id_house
    AND l.business_context = hcs.business_context
    AND l.house_neighborhood = hcs.house_neighborhood
LEFT JOIN
    datalake_atlas_pricing_report.house_condo_metrics hic
ON
    l.id_house = hic.id_house
    AND l.house_neighborhood = hic.house_neighborhood