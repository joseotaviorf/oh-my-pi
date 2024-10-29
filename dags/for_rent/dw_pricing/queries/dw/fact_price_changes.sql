SELECT
    COALESCE(pri.id_price_change, -1) AS sk_pricing,
    COALESCE(pre.id_prediction_change, -1) AS sk_price_predicted,
    pri.id_house AS sk_house,
    COALESCE(pri.id_house_listing, -1) AS sk_house_listing,
    COALESCE(pri.id_user_revision, -1) AS sk_user,
    pri.days_with_pricing_scheme,
    pri.ts_price_started,
    ts_price_ended,
    NOW() AS ts_load
FROM
    datalake_ebdb_pricing.listing_price_change AS pri
LEFT JOIN
    datalake_ebdb_pricing.listing_prediction_changes AS pre
        ON pre.id_house = pri.id_house
        AND pre.id_house_listing = pri.id_house_listing
        AND pri.ts_price_started BETWEEN pre.ts_calculator_result_started AND COALESCE(pre.ts_calculator_result_ended, CURRENT_TIMESTAMP)
