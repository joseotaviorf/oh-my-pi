SELECT
    id_organization AS sk_business_unit,
    name AS business_unit_name,
    created_by,
    updated_by,
    status = 'A' AS is_active,
    dt_effective_started,
    dt_effective_ended,
    ts_created,
    ts_updated,
    ts_load
FROM
    datalake_pin_core_clean.hr_organization
WHERE
    classification_code = 'FUN_BUSINESS_UNIT'