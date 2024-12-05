SELECT 
    CAST(CONCAT(slpc.id_house, BIGINT(DATE_FORMAT(slpc.ts_price_started, 'yyyyMMdd'))) AS BIGINT) AS sk_price_change,
    slpc.id_house AS sk_house,
    slpc.id_user_revision AS sk_user_revision,
    slpc.id_owner AS sk_owner,
    slpc.id_region AS sk_region,
    dps.sk_sale_price_segment,
    BIGINT(DATE_FORMAT(slpc.ts_price_started, 'yyyyMMdd')) AS sk_price_started_date,
    COALESCE(BIGINT(DATE_FORMAT(slpc.ts_price_ended, 'yyyyMMdd')), -1) AS sk_price_ended_date,
    slpc.status_history,
    slpc.calculator_certainty AS predict_certainty,
    slpc.change_type,
    slpc.change_number AS change,
    slpc.days_with_pricing_scheme,
    slpc.sale_price AS price,
    slpc.lag_sale_price AS previous_price,
    slpc.last_price_variation AS previous_price_variation,
    slpc.first_price_variation,
    slpc.calculator_min_sale_price AS min_predicted_price,
    slpc.calculator_p30_sale_price AS p30_predicted_price,
    slpc.calculator_sale_price AS predicted_price,
    slpc.calculator_p70_sale_price AS p70_predicted_price,
    slpc.calculator_max_sale_price AS max_predicted_price,
    slpc.is_first_price,
    slpc.is_last_price,
    slpc.is_smart_price_change,
    NOW() AS ts_load
FROM
    datalake_sale_listings.sale_listing_price_changes AS slpc
LEFT JOIN
    dw_sale.dim_sale_price_segment AS dps
        ON slpc.price_segment = dps.price_segment
