SELECT
    listing_id AS id_listing,
    DATE(dt_alloc) AS dt_alloc,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.sale_listings_2025
