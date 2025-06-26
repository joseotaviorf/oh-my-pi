SELECT DISTINCT
    md.id_business_unit AS sk_business_unit,
    o.name AS business_unit_name,
    wr.legal_employer_name,
    wr.legislation_code,
    NOW() AS ts_load
FROM
    datalake_pin.movement_details AS md
JOIN 
    datalake_hr_system.work_relationships AS wr 
        ON md.id_period_of_service = wr.id_period_of_service
JOIN 
    datalake_hr_system_clean.organizations AS o
        ON md.id_business_unit = o.id_organization