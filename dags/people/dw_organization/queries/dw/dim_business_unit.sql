/* Interim hardcoded CNPJ on business_unit_name for QuintoAndar SP (including Deel - QuintoAndar),
   MG, SC, and Atta until PIN Oracle Fusion establishment registrations are linked to
   FUN_BUSINESS_UNIT rows. Atta sourced from Oracle xle_registrations (ATTA FRANCHISING LTDA). */
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
    CASE
        WHEN business_unit_name = 'QuintoAndar MG' THEN '16.788.643/0021-25'
        WHEN business_unit_name = 'QuintoAndar SC' THEN '16.788.643/0022-06'
        WHEN business_unit_name IN ('QuintoAndar SP', 'Deel - QuintoAndar') THEN '16.788.643/0001-81'
        WHEN business_unit_name = 'Atta' THEN '19.623.189/0001-05'
        ELSE NULL
    END AS cnpj,
    NOW() AS ts_load
FROM
    datalake_people.business_unit
WHERE
    is_current = TRUE
