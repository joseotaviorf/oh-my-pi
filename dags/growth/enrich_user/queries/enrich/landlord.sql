SELECT DISTINCT
    id_snapshot,
    id_owner AS id_user,
    'landlord' AS client_type,
    journey_step,
    persona_step,
    total_houses,
    ongoing_houses,
    is_offboarding,
    is_ongoing,
    is_onboarding,
    is_contract_to_entrance,
    is_visits_to_offer,
    is_listing_and_search,
    is_pre_contract,
    is_post_contract,
    is_pp_multi,
    ongoing_houses >= 5 OR is_pp_multi AS is_pp_multi_5_more_ongoing_houses,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_landlord_journey.landlord_journey_step
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
