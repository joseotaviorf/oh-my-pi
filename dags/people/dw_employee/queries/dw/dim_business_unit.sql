SELECT DISTINCT
    a.id_business_unit AS sk_business_unit,
    o.name AS business_unit_name,
    wr.legal_employer_name,
    wr.legislation_code,
    NOW() AS ts_load
FROM
    datalake_hr_system.assignments AS a
JOIN 
    datalake_hr_system.work_relationships AS wr 
        ON a.id_period_of_service = wr.id_period_of_service
JOIN 
    datalake_hr_system_clean.organizations AS o
        ON a.id_business_unit = o.id_organization