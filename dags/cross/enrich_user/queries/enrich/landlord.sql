SELECT DISTINCT
    ljs.id_snapshot,
    ljs.id_owner AS id_user,
    u.id_country,
    'landlord' AS client_type,
    COALESCE(ct.code, 'Undefined') AS country_code,
    u.main_phone,
    u.name,
    u.email,
    u.cpf,
    ljs.journey_step,
    ljs.persona_step,
    u.is_active,
    u.is_blocked,
    ljs.is_offboarding,
    ljs.is_ongoing,
    ljs.is_onboarding,
    ljs.is_contract_to_entrance,
    ljs.is_visits_to_offer,
    ljs.is_listing_and_search,
    ljs.is_pre_contract,
    ljs.is_post_contract,
    ljs.is_pp_multi,
    DATE(u.dt_birth) AS dt_birth,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_landlord_journey.landlord_journey_step AS ljs
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON ljs.id_owner = u.id
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.id = u.id_country
WHERE
  ljs.year = {year}
  AND ljs.month = {month}
  AND ljs.day = {day}
