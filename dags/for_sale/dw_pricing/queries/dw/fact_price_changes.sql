WITH prediction AS (
    SELECT
        pri.id_price_change AS sk_pricing,
        COALESCE(pre.id_prediction_change, -1) AS sk_price_predicted,
        pri.id_house AS sk_house,
        pri.id_house_listing AS sk_house_listing,
        COALESCE(pri.id_user_revision, -1) AS sk_user,
        pri.days_with_pricing_scheme,
        pri.business_context,
        pri.ts_price_started,
        ts_price_ended
    FROM
        datalake_ebdb_pricing.listing_price_change AS pri
    LEFT JOIN
        datalake_ebdb_pricing.listing_prediction_changes AS pre
            ON pre.id_house = pri.id_house
            AND pre.id_house_listing = pri.id_house_listing
            AND pre.ts_calculator_result_started BETWEEN pri.ts_price_started AND COALESCE(pri.ts_price_ended, CURRENT_TIMESTAMP)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY sk_pricing ORDER BY pre.ts_calculator_result_started, COALESCE(pre.ts_calculator_result_ended, CURRENT_TIMESTAMP)) = 1
)
SELECT
    p.sk_pricing,
    p.sk_price_predicted,
    COALESCE(hsc.id_suggestion_change, -1) AS sk_price_suggested,
    p.sk_house,
    p.sk_house_listing,
    p.sk_user,
    p.days_with_pricing_scheme,
    p.ts_price_started,
    p.ts_price_ended,
    NOW() AS ts_load
FROM
    prediction AS p
LEFT JOIN
    datalake_ebdb_pricing.house_suggestion_changes AS hsc
        ON hsc.id_house = p.sk_house
        AND p.business_context = hsc.business_context
        AND p.ts_price_started BETWEEN hsc.ts_suggestion_started AND COALESCE(hsc.ts_suggestion_ended, CURRENT_TIMESTAMP)
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY sk_pricing ORDER BY hsc.ts_suggestion_started DESC, COALESCE(hsc.ts_suggestion_ended, CURRENT_TIMESTAMP) DESC) = 1
