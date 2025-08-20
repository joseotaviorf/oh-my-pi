SELECT
    listing_id AS id_listing,
    dt_alloc,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.sale_ongoing_listings_date
