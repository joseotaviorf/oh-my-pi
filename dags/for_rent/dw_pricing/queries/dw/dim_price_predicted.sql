SELECT
    id_prediction_change AS sk_price_predicted,
    calculator_min_price AS min_price,
    calculator_p20_price AS p20_price,
    calculator_p30_price AS p30_price,
    calculator_p40_price AS p40_price,
    calculator_price AS estimated_price,
    calculator_p60_price AS p60_price,
    calculator_p70_price AS p70_price,
    calculator_p80_price AS p80_price,
    calculator_max_price AS max_price,
    calculator_certainty AS certainty,
    is_last_prediction,
    is_last_prediction_of_day,
    business_context,
    NOW() AS ts_load
FROM
    datalake_ebdb_pricing.listing_prediction_changes
