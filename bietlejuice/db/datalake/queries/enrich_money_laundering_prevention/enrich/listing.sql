SELECT 
    h.id AS id_house,
    sl.id_sale_listing,
    h.id_user,
    h.id_user_registrant,  
    h.sale_price AS listing_value,
    lbc.calculator_price,
    h.country_code,
    lbc.status,
    lbc.status_closing,
    h.compare_price_with_average,
    h.is_3p_supply,
    h.is_photographer_job_pending,
    h.is_verified,
    h.dt_creation AS ts_created,
    sl.ts_first_publication AS ts_first_sale_listing,
    sl.ts_last_publication AS ts_last_sale_listing
FROM
    datalake_ebdb_listing.house AS h
INNER JOIN datalake_sale_listings.sale_listing AS sl
    ON sl.id_house = h.id
LEFT JOIN datalake_ebdb_listing.listing_business_context AS lbc
    ON lbc.id_house = h.id