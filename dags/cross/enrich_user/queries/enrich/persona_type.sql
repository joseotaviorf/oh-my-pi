SELECT
    id_snapshot,
    id_user,
    1 AS id_user_type,
    id_country,
    client_type,
    country_code,
    main_phone,
    name,
    email,
    cpf,
    journey_step,
    persona_step,
    is_active,
    is_blocked,
    is_pp_multi,
    is_offboarding,
    is_ongoing,
    is_onboarding,
    is_contract_to_entrance,
    is_visits_to_offer,
    is_listing_and_search,
    is_pre_contract,
    is_post_contract,
    dt_birth,
    ts_user_created,
    ts_user_updated,
    year,
    month,
    day
FROM
    datalake_user.landlord
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
UNION ALL
SELECT
    id_snapshot,
    id_user,
    2 AS id_user_type,
    id_country,
    client_type,
    country_code,
    main_phone,
    name,
    email,
    cpf,
    journey_step,
    persona_step,
    is_active,
    is_blocked,
    NULL AS is_pp_multi,
    is_offboarding,
    is_ongoing,
    is_onboarding,
    is_contract_to_entrance,
    is_visits_to_offer,
    is_listing_and_search,
    is_pre_contract,
    is_post_contract,
    dt_birth,
    ts_user_created,
    ts_user_updated,
    year,
    month,
    day
FROM
    datalake_user.tenant_user
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
UNION ALL
SELECT
    id_snapshot,
    id_user,
    3 AS id_user_type,
    id_country,
    client_type,
    country_code,
    main_phone,
    name,
    email,
    cpf,
    NULL AS journey_step,
    NULL AS persona_step,
    is_active,
    is_blocked,
    NULL AS is_pp_multi,
    NULL AS is_offboarding,
    NULL AS is_ongoing,
    NULL AS is_onboarding,
    NULL AS is_contract_to_entrance,
    NULL AS is_visits_to_offer,
    NULL AS is_listing_and_search,
    NULL AS is_pre_contract,
    NULL AS is_post_contract,
    dt_birth,
    ts_user_created,
    ts_user_updated,
    year,
    month,
    day
FROM
    datalake_user.photographer_user
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
UNION ALL
SELECT
    id_snapshot,
    id_user,
    4 AS id_user_type,
    id_country,
    client_type,
    country_code,
    main_phone,
    name,
    email,
    cpf,
    NULL AS journey_step,
    NULL AS persona_step,
    is_active,
    is_blocked,
    NULL AS is_pp_multi,
    NULL AS is_offboarding,
    NULL AS is_ongoing,
    NULL AS is_onboarding,
    NULL AS is_contract_to_entrance,
    NULL AS is_visits_to_offer,
    NULL AS is_listing_and_search,
    NULL AS is_pre_contract,
    NULL AS is_post_contract,
    dt_birth,
    ts_user_created,
    ts_user_updated,
    year,
    month,
    day
FROM
    datalake_user.broker_user
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
