WITH house_on_market_median_prices AS (
    SELECT
        id_house,
        business_context,
        neighborhood,
        similar_house_status,
        MEDIAN(similar_house_price) AS on_market_price_median,
        MEDIAN(similar_price_m2) AS on_market_price_by_square_meter
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE similar_status = 'PUBLISHED'
    GROUP BY 1,2,3,4
),

house_off_market_median_prices AS (
    SELECT
        id_house,
        business_context,
        neighborhood,
        similar_house_status,
        MEDIAN(similar_house_price) AS off_market_price_median,
        MEDIAN(similar_price_m2) AS off_market_price_by_square_meter
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE
        similar_status != 'PUBLISHED'
        AND similar_days_to_contract_sign IS NULL
    GROUP BY 1,2,3,4
),

house_negotiated_median_days_to_contract_sign AS (
    SELECT
        id_house,
        business_context,
        neighborhood,
        MEDIAN(similar_days_to_contract_sign) AS median_days_to_contract_sign
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE
        similar_status != 'PUBLISHED'
        AND (similar_days_to_contract_sign IS NULL OR similar_days_to_contract_sign > 0)
    GROUP BY 1, 2, 3
),

house_negotiated_median_price AS (
    SELECT
        id_house,
        business_context,
        neighborhood,
        similar_house_status,
        MEDIAN(similar_negotiated_price) AS negotiated_price_median,
        MEDIAN(similar_negotiated_price_m2) AS negotiated_price_by_square_meter
    FROM datalake_atlas_pricing_report.similar_listings
    WHERE
        similar_status != 'PUBLISHED'
        AND (similar_days_to_contract_sign IS NULL OR similar_days_to_contract_sign > 0)
    GROUP BY 1,2,3,4
)

SELECT DISTINCT
    l.id_house,
    l.business_context,
    l.neighborhood,
    hon.on_market_price_median,
    hon.on_market_price_by_square_meter,
    hoff.off_market_price_median,
    hoff.off_market_price_by_square_meter,
    hcs.median_days_to_contract_sign,
    hnp.negotiated_price_median,
    hnp.negotiated_price_by_square_meter,
    hic.condominium_price_median,
    hic.urban_property_tax_median
FROM datalake_atlas_pricing_report.similar_listings l
LEFT JOIN house_on_market_median_prices hon
    ON l.id_house = hon.id_house
    AND l.business_context = hon.business_context
LEFT JOIN house_off_market_median_prices hoff
    ON l.id_house = hoff.id_house
    AND l.business_context = hoff.business_context
LEFT JOIN house_negotiated_median_days_to_contract_sign hcs
    ON l.id_house = hcs.id_house
    AND l.business_context = hcs.business_context
LEFT JOIN house_negotiated_median_price hnp
    ON l.id_house = hnp.id_house
    AND l.business_context = hnp.business_context
LEFT JOIN datalake_atlas_pricing_report.house_condo_metrics hic
    ON l.id_house = hic.id_house
