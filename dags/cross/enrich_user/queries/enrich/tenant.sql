SELECT DISTINCT
    id_snapshot,
    id_client AS id_user,
    'tenant' AS client_type,
    journey_step,
    persona_step,
    is_offboarding,
    is_ongoing,
    is_onboarding,
    is_contract_to_entrance,
    is_visits_to_offer,
    is_listing_and_search,
    is_pre_contract,
    is_post_contract,
    year,
    month,
    day
FROM
    datalake_tenant_journey.tenant_journey_step
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
