SELECT
    NULLIF(city_group, '') AS city_group,
    NULLIF(rental_administrator, '') AS rental_administrator,
    NULLIF(business_context, '') AS business_context,
    CAST(REPLACE(NULLIF(ongoing_listings, ''), ',', '') AS FLOAT) AS ongoing_listings,
    CAST(REPLACE(NULLIF(relisting, ''), ',', '') AS FLOAT) AS relisting,
    CAST(REPLACE(NULLIF(recovered, ''), ',', '') AS FLOAT) AS recovered,
    CAST(REPLACE(NULLIF(suspensions, ''), ',', '') AS FLOAT) AS suspensions,
    CAST(REPLACE(NULLIF(depublications, ''), ',', '') AS FLOAT) AS depublications,
    CAST(REPLACE(NULLIF(ended_rentals, ''), ',', '') AS FLOAT) AS ended_rentals,
    CAST(REPLACE(NULLIF(erc, ''), ',', '') AS FLOAT) AS erc,
    CAST(REPLACE(NULLIF(ongoing_rentals, ''), ',', '') AS FLOAT) AS ongoing_rentals,
    CAST(REPLACE(NULLIF(new_rental, ''), ',', '') AS FLOAT) AS new_rental,
    CAST(REPLACE(NULLIF(new_first_rental, ''), ',', '') AS FLOAT) AS new_first_rental,
    CAST(NULLIF(date, '') AS DATE) AS date
FROM
    datalake_gsheets_raw.ongoing_listings_targets_2025    									