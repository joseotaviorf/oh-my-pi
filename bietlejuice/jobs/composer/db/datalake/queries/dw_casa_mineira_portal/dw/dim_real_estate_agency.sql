SELECT 
    CAST(rea.id AS INT) AS sk_real_estate_agency,
    COALESCE(CAST(DATE_FORMAT(rea.ts_created, 'yyyyMMdd') AS INT), -1) AS sk_real_estate_agency_created_date,
    COALESCE(CAST(DATE_FORMAT(rea.ts_disabled, 'yyyyMMdd') AS INT), -1) AS sk_real_estate_agency_disabled_date,
    CAST(rea.id AS INT) AS id_real_estate_agency,
    rea.real_estate_agency_name,
    rea.real_estate_agency_full_name,
    uf.uf_name AS uf,
    city.city_name AS city,
    rea.neighborhood,
    rea.address,
    rea.zip_code,
    rea.lat,
    rea.lng,
    rea.website,
    rea.integration_format,
    rea.notification_type,
    rea.person_type IS NOT DISTINCT FROM 'juridica' AS is_juridical_person,
    rea.person_type IS NOT DISTINCT FROM 'fisica' AS is_natural_person,
    rea.ts_created AS ts_real_estate_agency_created,
    rea.ts_disabled AS ts_real_estate_agency_disabled,
    NOW() AS ts_load
FROM
    datalake_casa_mineira_portal_clean.real_estate_agency AS rea
JOIN
    datalake_casa_mineira_portal_clean.city AS city 
        ON city.id = rea.id_city
JOIN
    datalake_casa_mineira_portal_clean.uf AS uf 
        ON uf.id = city.id_uf
