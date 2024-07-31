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
    TO_DATE(date) AS dt_budget
FROM
    datalake_gsheets_raw.rent_ongoing_listings_budget_2024
