SELECT
    CAST(cr.id_region AS BIGINT) AS id,
    cr.id_city_region AS id_city,
    cr.id_macro_region AS id_macro_region,
    cr.id_state AS id_state,
    CAST(cr.id_country AS INTEGER) AS id_country,
    cr.country_code AS country_code,
    cr.level AS level,
    COALESCE(NULLIF(cr.region_name, ''), ar.neighbourhood) AS name,
    cr_parent.region_name AS macro_region_name,
    COALESCE(cr.city_region_name, ar.city) AS city_name,
    ar.city_group AS city_group,
    COALESCE(cr.region_phone_ddd, CAST(ar.ddd AS STRING)) AS city_ddd,
    ar.region_code AS region_code,
    ar.region_code_deprecated AS region_code_deprecated,
    ar.region_code_inspector AS region_code_inspector,
    cr.state_abbreviation AS short_region_name,
    CASE
        WHEN COALESCE(cr.city_region_name, ar.city) IN ('Rio de Janeiro', 'Campinas')
            THEN COALESCE(cr.city_region_name, ar.city)
        WHEN COALESCE(cr.city_region_name, ar.city) IN (
            'São Paulo',
            'São Bernardo do Campo',
            'São Caetano do Sul',
            'Santo André',
            'Guarulhos',
            'Osasco',
            'Barueri'
        ) THEN 'Grande São Paulo'
        ELSE NULL
    END AS greater_region,
    ar.regional AS regional,
    ar.regional_deprecated AS regional_deprecated,
    ar.regional_inspection AS regional_inspection,
    ar.tier AS tier,
    cr.country_name AS country_name,
    (cr.level = 'Cidade') AS is_city,
    cr.has_rent_operation AS has_rent_operation,
    cr.has_sale_operation AS has_sale_operation,
    cr.ts_region_created AS ts_created,
    cr.ts_region_updated AS ts_updated,
    cr.sk_core_region AS sk_core_region,
    cr.country_default_timezone AS country_default_timezone,
    cr.year AS year,
    cr.month AS month,
    cr.day AS day
FROM
    core_region.region AS cr
LEFT JOIN
    core_region.region AS cr_parent
    ON cr_parent.id_region = cr.id_macro_region
LEFT JOIN
    datalake_gsheets_clean.auxiliary_region AS ar
    ON cr.id_region = ar.id
