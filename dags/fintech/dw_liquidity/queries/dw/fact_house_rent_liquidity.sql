SELECT
    id AS sk_house,
    latest_house_listing_id AS sk_house_listing,
    rent_liquidity_model_version,
    rent_liquidity_score,
    ts_publicated,
    timestamp AS ts_created,
    NOW() AS ts_load
FROM
    wonka.house_rent_liquidity__latest
