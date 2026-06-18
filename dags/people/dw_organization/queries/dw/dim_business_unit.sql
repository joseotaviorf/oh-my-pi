SELECT
    id_organization AS sk_business_unit,
    business_unit_name,
    CASE
        WHEN business_unit_name = 'Deel - QuintoAndar' THEN 'QuintoAndar SP'
        WHEN business_unit_name IN (
            'Classifieds Latam',
            'OneLoop S.R.L.',
            'Grupo Navent S.R.L.',
            'Dridco S.A.U.',
            'SOLUSER SOLUCIONES Y SERVICIOS SA DE CV',
            'DRIDCO MEXICO SA DE CV',
            'TECNOLOGÍA PARA INMOBILIARIAS SA DE CV'
        ) THEN 'Classifieds'
        WHEN business_unit_name = 'Atta' THEN 'ATTA'
        WHEN business_unit_name = 'Benvi MX' THEN 'Benvi México'
        WHEN business_unit_name IN ('Benvi PT', 'Remote') THEN 'QuintoAndar Portugal'
        ELSE business_unit_name
    END AS consolidated_business_unit_name,
    NOW() AS ts_load
FROM
    datalake_people.business_unit
WHERE
    is_current = TRUE
