SELECT
    cidade,
    ongoing_listing,
    FB AS sale_model,
    halfyear,
    quarter,
    week,
    month,
    year,
    date
FROM
    datalake_gsheets_raw.sale_ongoing_listings_targets
