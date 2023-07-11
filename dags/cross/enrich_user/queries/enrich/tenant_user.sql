SELECT DISTINCT
    tjs.id_snapshot,
    tjs.id_client AS id_user,
    u.id_country,
    'tenant' AS client_type,
    COALESCE(ct.code, 'Undefined') AS country_code,
    u.main_phone,
    u.name,
    u.email,
    u.cpf,
    tjs.tenant_journey_step,
    tjs.tenant_persona_step,
    u.is_active,
    u.is_blocked,
    tjs.is_offboarding AS is_tenant_offboarding,
    tjs.is_ongoing AS is_tenant_ongoing,
    tjs.is_onboarding AS is_tenant_onboarding,
    tjs.is_contract_to_entrance AS is_tenant_contract_to_entrance,
    tjs.is_visits_to_offer AS is_tenant_visits_to_offer,
    tjs.is_listing_and_search AS is_tenant_listing_and_search,
    tjs.is_pre_contract AS is_tenant_pre_contract,
    tjs.is_post_contract AS is_tenant_post_contract,
    DATE(u.dt_birth) AS dt_birth,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated,
    tjs.year,
    tjs.month,
    tjs.day
FROM
    datalake_tenant_journey.tenant_journey_step AS tjs
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON tjs.id_client = u.id
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.id = u.id_country
WHERE
  tjs.year = {year}
  AND tjs.month = {month}
  AND tjs.day = {day}
