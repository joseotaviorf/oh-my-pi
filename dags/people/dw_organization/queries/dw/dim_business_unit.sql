SELECT
    id_organization AS sk_business_unit,
    business_unit_name,
    NOW() AS ts_load
FROM
    datalake_people.business_unit
WHERE
    is_current = TRUE
