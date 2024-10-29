SELECT
    id_prediction_change AS sk_price_predicted,
    id_house AS sk_house,
    COALESCE(id_house_listing, -1) AS sk_house_listing,
    ts_calculator_result_started AS ts_price_predicted_started,
    ts_calculator_result_ended AS ts_price_predicted_ended,
    NOW() AS ts_load
FROM
    datalake_ebdb_pricing.listing_prediction_changes
