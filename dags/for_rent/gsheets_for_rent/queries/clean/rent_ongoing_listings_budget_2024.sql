SELECT
    business_context,
    city_group,
    rental_administrator,
    CAST(REPLACE(depublications, ',', '') AS DECIMAL(14,6)) AS depublications,  
    CAST(REPLACE(ongoing_listings, ',', '') AS DECIMAL(14,6)) AS ongoing_listings,  
    CAST(REPLACE(recovered, ',', '') AS DECIMAL(14,6)) AS recovered,  
    CAST(REPLACE(relisting, ',', '') AS DECIMAL(14,6)) AS relisting,  
    CAST(REPLACE(suspensions, ',', '') AS DECIMAL(14,6)) AS suspensions,
    CAST(REPLACE(ended_rentals, ',', '') AS DECIMAL(14,6)) AS ended_rentals,
    CAST(REPLACE(erc, ',', '') AS DECIMAL(14,6)) AS erc,
    CAST(REPLACE(ongoing_rentals, ',', '') AS DECIMAL(14,6)) AS ongoing_rentals,
    CAST(REPLACE(new_rental, ',', '') AS DECIMAL(14,6)) AS new_rental,
    CAST(REPLACE(new_first_rental, ',', '') AS DECIMAL(14,6)) AS new_first_rental,
    TO_DATE(date, 'yyyy-M-d') AS dt_created
FROM
    datalake_gsheets_raw.rent_ongoing_listings_budget_2024
