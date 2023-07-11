SELECT
    po.id_snapshot,
    po.id_user,
    1 AS id_user_type,
    po.id_country,
    po.client_type,
    po.country_code,
    po.main_phone,
    po.name,
    po.email,
    po.cpf,
    NULL AS tenant_journey_step,
    NULL AS tenant_persona_step,
    po.is_active,
    po.is_blocked,
    po.is_pp_multi,
    NULL AS is_tenant_offboarding,
    NULL AS is_tenant_ongoing,
    NULL AS is_tenant_onboarding,
    NULL AS is_tenant_contract_to_entrance,
    NULL AS is_tenant_visits_to_offer,
    NULL AS is_tenant_listing_and_search,
    NULL AS is_tenant_pre_contract,
    NULL AS is_tenant_post_contract,
    po.dt_birth,
    po.ts_user_created,
    po.ts_user_updated,
    po.year,
    po.month,
    po.day
FROM
    datalake_user.property_owner AS po
WHERE
    po.year = {year}
    AND po.month = {month}
    AND po.day = {day}
UNION ALL
SELECT
    tu.id_snapshot,
    tu.id_user,
    2 AS id_user_type,
    tu.id_country,
    tu.client_type,
    tu.country_code,
    tu.main_phone,
    tu.name,
    tu.email,
    tu.cpf,
    tu.tenant_journey_step,
    tu.tenant_persona_step,
    tu.is_active,
    tu.is_blocked,
    NULL AS is_pp_multi,
    tu.is_tenant_offboarding,
    tu.is_tenant_ongoing,
    tu.is_tenant_onboarding,
    tu.is_tenant_contract_to_entrance,
    tu.is_tenant_visits_to_offer,
    tu.is_tenant_listing_and_search,
    tu.is_tenant_pre_contract,
    tu.is_tenant_post_contract,
    tu.dt_birth,
    tu.ts_user_created,
    tu.ts_user_updated,
    tu.year,
    tu.month,
    tu.day
FROM
    datalake_user.tenant_user AS tu
WHERE
    tu.year = {year}
    AND tu.month = {month}
    AND tu.day = {day}
UNION ALL
SELECT
    phu.id_snapshot,
    phu.id_user,
    3 AS id_user_type,
    phu.id_country,
    phu.client_type,
    phu.country_code,
    phu.main_phone,
    phu.name,
    phu.email,
    phu.cpf,
    NULL AS tenant_journey_step,
    NULL AS tenant_persona_step,
    phu.is_active,
    phu.is_blocked,
    NULL AS is_pp_multi,
    NULL AS is_tenant_offboarding,
    NULL AS is_tenant_ongoing,
    NULL AS is_tenant_onboarding,
    NULL AS is_tenant_contract_to_entrance,
    NULL AS is_tenant_visits_to_offer,
    NULL AS is_tenant_listing_and_search,
    NULL AS is_tenant_pre_contract,
    NULL AS is_tenant_post_contract,
    phu.dt_birth,
    phu.ts_user_created,
    phu.ts_user_updated,
    phu.year,
    phu.month,
    phu.day
FROM
    datalake_user.photographer_user AS phu
WHERE
    phu.year = {year}
    AND phu.month = {month}
    AND phu.day = {day}
UNION ALL
SELECT
    bu.id_snapshot,
    bu.id_user,
    4 AS id_user_type,
    bu.id_country,
    bu.client_type,
    bu.country_code,
    bu.main_phone,
    bu.name,
    bu.email,
    bu.cpf,
    NULL AS tenant_journey_step,
    NULL AS tenant_persona_step,
    bu.is_active,
    bu.is_blocked,
    NULL AS is_pp_multi,
    NULL AS is_tenant_offboarding,
    NULL AS is_tenant_ongoing,
    NULL AS is_tenant_onboarding,
    NULL AS is_tenant_contract_to_entrance,
    NULL AS is_tenant_visits_to_offer,
    NULL AS is_tenant_listing_and_search,
    NULL AS is_tenant_pre_contract,
    NULL AS is_tenant_post_contract,
    bu.dt_birth,
    bu.ts_user_created,
    bu.ts_user_updated,
    bu.year,
    bu.month,
    bu.day
FROM
    datalake_user.broker_user AS bu
WHERE
    bu.year = {year}
    AND bu.month = {month}
    AND bu.day = {day}
