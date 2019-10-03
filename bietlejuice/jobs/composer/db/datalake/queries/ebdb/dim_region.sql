SELECT
    r.id_region AS sk_region,
    coalesce(r.id_region, ar.id) AS id_region,
    r.level,
    coalesce(r.name, ar.neighbourhood) AS name,
    r.id_macro,
    r.macro_name,
    r.id_city,
    coalesce(ar.city, r.city_name) AS city_name,
    ar.city_group,
    ar.ddd AS city_ddd,
    ar.region_code,
    ar.region_code_deprecated,
    ar.state AS short_region_name,
    ar.long_region_name,
    CASE
        WHEN coalesce(r.city_name, ar.city) IN ('Rio de Janeiro') THEN coalesce(r.city_name, ar.city)
        WHEN coalesce(r.city_name, ar.city) IN ('Campinas') THEN coalesce(r.city_name, ar.city)
        WHEN coalesce(r.city_name, ar.city) IN
            ('São Paulo',
            'São Bernardo do Campo',
            'São Caetano do Sul',
            'Santo André',
            'Guarulhos',
            'Osasco',
            'Barueri') THEN 'Grande São Paulo'
        ELSE NULL
    END AS greater_region,
    ar.regional,
    r.ts_created,
    r.ts_updated
FROM
    datalake_ebdb_clean.region AS r
    LEFT JOIN files.aux_regiao AS ar
        ON r.id_region = ar.id
