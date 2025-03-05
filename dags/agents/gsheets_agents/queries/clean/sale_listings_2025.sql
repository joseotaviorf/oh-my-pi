SELECT
    listing_id AS id_listing,
    DATE(dt_alloc)
FROM
    datalake_gsheets_raw.sale_listings_2025
