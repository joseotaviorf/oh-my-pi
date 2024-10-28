SELECT
    id_price_change AS sk_pricing,
    price,
    previous_price,
    last_price_variation,
    first_price_variation,
    change_type,
    change_number,
    NOW() AS ts_load
FROM
    datalake_ebdb_pricing.listing_price_change
