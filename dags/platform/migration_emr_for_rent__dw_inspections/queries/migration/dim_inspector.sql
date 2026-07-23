SELECT DISTINCT
    COALESCE(id_inspector, -1) AS sk_inspector,
    inspector_name,
    inspector_email,
    inspector_corporate_name,
    beneficiary_name,
    employee_contract_type,
    company,
    status,
    operating_city,
    operating_regions,
    transportation_type,
    dt_start,
    dt_end,
    NOW() AS ts_load
FROM
    datalake_gsheets_clean.inspectors_control