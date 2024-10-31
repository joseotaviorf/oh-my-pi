WITH ll_and_tt_journeys AS (
    SELECT
        id_snapshot,
        id_user,
        1 AS id_user_type,
        client_type,
        journey_step,
        persona_step,
        is_pp_multi,
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
        client_type,
        journey_step,
        persona_step,
        NULL AS is_pp_multi,
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
        datalake_user.tenant
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
),
ll_and_tt AS (
    SELECT
        ltj.id_snapshot,
        ltj.id_user,
        ltj.id_user_type,
        u.id_country,
        ltj.client_type,
        u.main_phone,
        u.name,
        u.email,
        u.cpf,
        ltj.journey_step,
        ltj.persona_step,
        u.is_active,
        u.is_blocked,
        ltj.is_pp_multi,
        ltj.is_offboarding,
        ltj.is_ongoing,
        ltj.is_onboarding,
        ltj.is_contract_to_entrance,
        ltj.is_visits_to_offer,
        ltj.is_listing_and_search,
        ltj.is_pre_contract,
        ltj.is_post_contract,
        DATE(u.dt_birth) AS dt_birth,
        u.ts_created AS ts_user_created,
        u.ts_updated AS ts_user_updated,
        ltj.year,
        ltj.month,
        ltj.day
    FROM
        ll_and_tt_journeys AS ltj
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON ltj.id_user = u.id
    LEFT JOIN
        datalake_ebdb_clean.country AS ct
            ON ct.id = u.id_country
)
SELECT
    id_snapshot,
    id_user,
    id_user_type,
    id_country,
    client_type,
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
    ll_and_tt
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
