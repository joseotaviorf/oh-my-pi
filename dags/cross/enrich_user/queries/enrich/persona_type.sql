SELECT
    po.id_user,
    po.id_country,
    po.client_type,
    po.country_code,
    po.main_phone,
    po.name,
    po.email,
    po.cpf,
    po.is_active,
    po.is_blocked,
    po.is_pp_multi,
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
    tu.id_user,
    tu.id_country,
    tu.client_type,
    tu.country_code,
    tu.main_phone,
    tu.name,
    tu.email,
    tu.cpf,
    tu.is_active,
    tu.is_blocked,
    NULL AS is_pp_multi,
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
    phu.id_user,
    phu.id_country,
    phu.client_type,
    phu.country_code,
    phu.main_phone,
    phu.name,
    phu.email,
    phu.cpf,
    phu.is_active,
    phu.is_blocked,
    NULL AS is_pp_multi,
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
    bu.id_user,
    bu.id_country,
    bu.client_type,
    bu.country_code,
    bu.main_phone,
    bu.name,
    bu.email,
    bu.cpf,
    bu.is_active,
    bu.is_blocked,
    NULL AS is_pp_multi,
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
