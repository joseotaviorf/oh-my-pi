SELECT
    city_group,
    rental_administrator,
    business_context,
    ongoing_listings,
    relisting,
    recovered,
    suspensions,
    depublications,
    ended_rentals,
    erc,
    NULL AS ongoing_rentals,
    NULL AS new_rental,
    NULL AS new_first_rental,
    dt_budget
FROM
    datalake_gsheets_clean.rent_ongoing_listings_budget_2024
UNION ALL
SELECT
    city_group,
    rental_administrator,
    business_context,
    ongoing_listings,
    relisting,
    recovered,
    suspensions,
    depublications,
    ended_rentals,
    erc,
    ongoing_rentals,
    new_rental,
    new_first_rental,
    date AS dt_budget
FROM
    datalake_gsheets_clean.ongoing_listings_targets_2025