SELECT
    id_prediction_change AS sk_price_predicted,
    calculator_min_price AS min_price,
    calculator_p30_price AS p30_price,
    calculator_price AS estimated_price,
    calculator_p70_price AS p70_price,
    calculator_max_price AS max_price,
    calculator_certainty AS certainty,
    business_context,
    NOW() AS ts_load
FROM
    datalake_ebdb_pricing.listing_prediction_changes
